import XCTest
@testable import OneRoot

/// Verify copies and one-at-a-time copying (#64).
final class VerifyAndQueueTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @discardableResult
    private func write(_ data: Data, _ path: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    // MARK: FileVerifier

    func testMatchingFilesAndFoldersPass() throws {
        let big = bytes(3 << 20) // more than one chunk
        try write(big, "a/file.bin"); try write(big, "b/file.bin")
        try write(Data("x".utf8), "a/sub/small.txt"); try write(Data("x".utf8), "b/sub/small.txt")
        try write(Data(), "a/empty"); try write(Data(), "b/empty")
        var checked: Int64 = 0

        try FileVerifier.verify(tempDirectory.appendingPathComponent("a"), matches: tempDirectory.appendingPathComponent("b"), cancellation: CancellationFlag()) { checked = $0 }

        XCTAssertEqual(checked, Int64(big.count + 1))
    }

    func testOneChangedByteFails() throws {
        var changed = bytes(2 << 20)
        let original = try write(changed, "original.bin")
        changed[1_500_000] ^= 0xFF
        let copy = try write(changed, "copy.bin")

        XCTAssertThrowsError(try FileVerifier.verify(original, matches: copy, cancellation: CancellationFlag())) { error in
            guard case FileVerificationError.contentsDiffer = error else { return XCTFail("\(error)") }
        }
    }

    func testDifferentLengthFails() throws {
        let original = try write(bytes(100), "original.bin")
        let copy = try write(bytes(99), "copy.bin")

        XCTAssertThrowsError(try FileVerifier.verify(original, matches: copy, cancellation: CancellationFlag()))
    }

    func testAMissingItemInAFolderFails() throws {
        try write(Data("1".utf8), "a/one.txt"); try write(Data("2".utf8), "a/two.txt")
        try write(Data("1".utf8), "b/one.txt")

        XCTAssertThrowsError(try FileVerifier.verify(tempDirectory.appendingPathComponent("a"), matches: tempDirectory.appendingPathComponent("b"), cancellation: CancellationFlag())) { error in
            guard case FileVerificationError.structureDiffers = error else { return XCTFail("\(error)") }
        }
    }

    func testSymlinksCompareWhereTheyPoint() throws {
        let a = tempDirectory.appendingPathComponent("a"), b = tempDirectory.appendingPathComponent("b")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: "target-one")
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: "target-two")

        XCTAssertThrowsError(try FileVerifier.verify(a, matches: b, cancellation: CancellationFlag()))
    }

    func testCancelledVerifyThrowsCancellation() throws {
        let a = try write(bytes(10), "a.bin"), b = try write(bytes(10), "b.bin")
        let flag = CancellationFlag()
        flag.cancel()

        XCTAssertThrowsError(try FileVerifier.verify(a, matches: b, cancellation: flag)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: Copying with Verify on

    private func verifyingService() -> FileSystemService {
        var service = FileSystemService()
        service.verifiesCopies = { true }
        service.verifiesSameDiskCopies = true
        service.queuesTransfers = { false }
        return service
    }

    func testVerifiedCopyOfFilesAndFoldersCompletes() async throws {
        let source = try write(bytes(1 << 20), "src/data.bin")
        try write(Data("n".utf8), "src/Folder/nested.txt")
        let destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try await verifyingService().copyItems([source, tempDirectory.appendingPathComponent("src/Folder")], to: destination) { _ in .skip }

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("data.bin")), try Data(contentsOf: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Folder/nested.txt").path))
    }

    // MARK: Metadata on shares that can't store it

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    private func copyWithXattr(storesNatively: Bool, keepSetting: Bool) async throws -> (hasXattr: Bool, contents: Data) {
        let source = try write(Data("hello".utf8), "src-\(UUID().uuidString)/tagged.txt")
        _ = source.withUnsafeFileSystemRepresentation { path in
            setxattr(path, "com.oneroot.test", "v", 1, 0, 0)
        }
        let destination = tempDirectory.appendingPathComponent("dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var service = FileSystemService()
        service.queuesTransfers = { false }
        service.storesMetadataNatively = { _ in storesNatively }
        service.keepsMetadataOnShares = { keepSetting }

        try await service.copyItems([source], to: destination) { _ in .skip }

        let copy = destination.appendingPathComponent("tagged.txt")
        let size = copy.withUnsafeFileSystemRepresentation { getxattr($0, "com.oneroot.test", nil, 0, 0, 0) }
        return (size > 0, try Data(contentsOf: copy))
    }
    #endif

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testMetadataIsLeftOffForSharesThatCantStoreIt() async throws {
        let result = try await copyWithXattr(storesNatively: false, keepSetting: false)
        XCTAssertFalse(result.hasXattr)
        XCTAssertEqual(result.contents, Data("hello".utf8), "contents are untouched")
    }
    #endif

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testMetadataIsKeptOnDisksAndWhenAskedFor() async throws {
        let onDisk = try await copyWithXattr(storesNatively: true, keepSetting: false)
        XCTAssertTrue(onDisk.hasXattr)
        let kept = try await copyWithXattr(storesNatively: false, keepSetting: true)
        XCTAssertTrue(kept.hasXattr)
    }
    #endif

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testTheBootDiskStoresMetadataNatively() {
        XCTAssertTrue(FileCopier.storesMetadataNatively(tempDirectory))
        XCTAssertTrue(FileCopier.storesMetadataNatively(tempDirectory.appendingPathComponent("not/yet/there")))
    }
    #endif

    // MARK: FileTransferQueue

    func testSameDiskOperationsNeedNoQueue() {
        let a = tempDirectory.appendingPathComponent("a"), b = tempDirectory.appendingPathComponent("b")
        XCTAssertTrue(FileTransferQueue.disks(for: [a], into: b).isEmpty, "a move or copy within one disk never waits")
        XCTAssertNotNil(FileTransferQueue.disk(of: tempDirectory.appendingPathComponent("not/yet/there")), "asks the nearest existing folder")
    }

    func testOverlappingDisksWaitTheirTurnAndDisjointOnesDont() async throws {
        let queue = FileTransferQueue()
        let first = UUID(), second = UUID(), unrelated = UUID()
        try await queue.acquire(id: first, disks: ["/Volumes/A", "/"], shouldStop: { false }, startNow: { false }, onWaiting: {})
        try await queue.acquire(id: unrelated, disks: ["/Volumes/C", "/Volumes/D"], shouldStop: { false }, startNow: { false }, onWaiting: {})

        let waited = WaitedFlag()
        let secondTask = Task {
            try await queue.acquire(id: second, disks: ["/Volumes/A", "/Volumes/B"], shouldStop: { false }, startNow: { false }, onWaiting: { waited.set() })
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(waited.isSet, "the second shares disk A, so it waits")

        await queue.release(id: first)
        try await secondTask.value
        let count = await queue.count
        XCTAssertEqual(count, 2)
    }

    func testStartNowAndCancelWhileWaiting() async throws {
        let queue = FileTransferQueue()
        try await queue.acquire(id: UUID(), disks: ["/Volumes/A"], shouldStop: { false }, startNow: { false }, onWaiting: {})

        let startNow = StartNowFlag()
        let jumping = Task { try await queue.acquire(id: UUID(), disks: ["/Volumes/A"], shouldStop: { false }, startNow: { startNow.isSet }, onWaiting: {}) }
        startNow.set()
        try await jumping.value

        let stop = StartNowFlag()
        let cancelled = Task { try await queue.acquire(id: UUID(), disks: ["/Volumes/A"], shouldStop: { stop.isSet }, startNow: { false }, onWaiting: {}) }
        try await Task.sleep(for: .milliseconds(100))
        stop.set()
        do {
            try await cancelled.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
        let count = await queue.count
        XCTAssertEqual(count, 2, "the cancelled one left the line")
    }
}

private final class WaitedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
