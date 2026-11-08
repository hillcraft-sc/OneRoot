import XCTest
@testable import OneRoot

private func copyItem(_ source: URL, to destination: URL, cancellation: CancellationFlag, onProgress: @escaping (Int64) -> Void) throws {
    try Platform.copyItem(source, to: destination, includeMetadata: true, cancellation: cancellation, onProgress: onProgress)
}

/// The copy engine — `FileCopier` on the Mac, `LinuxFileCopier` on Linux —
/// through `Platform.copyItem`.
final class FileCopierTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeTree() throws -> URL {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_000).write(to: folder.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 2_000).write(to: folder.appendingPathComponent("Sub/b.bin"))
        try Data(repeating: 3, count: 3_000).write(to: folder.appendingPathComponent("Sub/c.bin"))
        return folder
    }

    func testCopiesAFolderTreeAndReportsItsFullSize() throws {
        let source = try makeTree()
        let destination = tempDirectory.appendingPathComponent("Copy", isDirectory: true)
        var reported: [Int64] = []

        try copyItem(source, to: destination, cancellation: CancellationFlag()) { reported.append($0) }

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Sub/c.bin")), Data(repeating: 3, count: 3_000))
        XCTAssertEqual(reported.last, 6_000, "progress ends at the tree's total size, even when APFS clones instead of copying")
        XCTAssertEqual(reported, reported.sorted(), "progress never goes backwards")
    }

    // MARK: Pause

    func testAPausedCopyWaitsAndThenFinishesWhereItWas() async throws {
        let source = try makeTree()
        let destination = tempDirectory.appendingPathComponent("Copy", isDirectory: true)
        let flag = CancellationFlag()
        flag.pause()

        let copy = Task.detached { try copyItem(source, to: destination, cancellation: flag) { _ in } }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Sub/c.bin").path), "nothing more while paused")

        flag.resume()
        try await copy.value

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Sub/c.bin")), Data(repeating: 3, count: 3_000))
    }

    func testCancellingAPausedCopyStopsItAndRemovesThePartialCopy() async throws {
        let source = try makeTree()
        let destination = tempDirectory.appendingPathComponent("Copy", isDirectory: true)
        let flag = CancellationFlag()
        flag.pause()

        let copy = Task.detached { try copyItem(source, to: destination, cancellation: flag) { _ in } }
        try await Task.sleep(nanoseconds: 200_000_000)
        flag.cancel()

        do {
            try await copy.value
            XCTFail("a cancelled copy throws")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testKeepsModificationDatesAndCopiesSymlinksAsLinks() throws {
        let file = tempDirectory.appendingPathComponent("file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)
        let link = tempDirectory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "file.txt")

        let fileCopy = tempDirectory.appendingPathComponent("file copy.txt")
        let linkCopy = tempDirectory.appendingPathComponent("link copy")
        try copyItem(file, to: fileCopy, cancellation: CancellationFlag()) { _ in }
        try copyItem(link, to: linkCopy, cancellation: CancellationFlag()) { _ in }

        let copiedDate = try FileManager.default.attributesOfItem(atPath: fileCopy.path)[.modificationDate] as? Date
        XCTAssertEqual(copiedDate, past)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkCopy.path), "file.txt")
    }

    func testCancellingMidCopyThrowsAndRemovesThePartialCopy() throws {
        let source = try makeTree()
        let destination = tempDirectory.appendingPathComponent("Copy", isDirectory: true)
        let cancellation = CancellationFlag()

        XCTAssertThrowsError(try copyItem(source, to: destination, cancellation: cancellation) { _ in
            cancellation.cancel() // as if Cancel were clicked right after the first file
        }) { error in
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Sub/c.bin").path), "the source is untouched")
    }

    func testRefusesAnExistingDestinationAndLeavesItAlone() throws {
        let source = tempDirectory.appendingPathComponent("a.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        let destination = tempDirectory.appendingPathComponent("b.txt")
        try "existing".write(to: destination, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try copyItem(source, to: destination, cancellation: CancellationFlag()) { _ in })

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
    }

    func testAFailedCopyLeavesNothingBehind() throws {
        let source = try makeTree()
        let unreadable = source.appendingPathComponent("Sub/c.bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let destination = tempDirectory.appendingPathComponent("Copy", isDirectory: true)

        XCTAssertThrowsError(try copyItem(source, to: destination, cancellation: CancellationFlag()) { _ in }) { error in
            XCTAssertFalse(error is CancellationError)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

#if os(Linux)
/// What the Linux copy engine keeps.
final class LinuxFileCopierTests: XCTestCase {
    func testKeepsPermissionsAndTags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("run.sh")
        try "echo hi".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: script.path)
        try XDGTags.setTags(["Work"], on: script)

        let copy = root.appendingPathComponent("copy.sh")
        try copyItem(script, to: copy, cancellation: CancellationFlag()) { _ in }

        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber)?.intValue, 0o750)
        XCTAssertEqual(XDGTags.tags(of: copy), ["Work"])
    }
}
#endif

#if os(Linux)
extension FileCopierTests {
    /// A copy into a read-only folder fails with the system's own words, not
    /// a generic write error (the File Operations panel shows this text).
    func testCopyIntoReadOnlyFolderSaysPermissionDenied() throws {
        try XCTSkipIf(geteuid() == 0, "root can write anywhere")
        let source = tempDirectory.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: source)
        let locked = tempDirectory.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try Platform.copyItem(source, to: locked.appendingPathComponent("a.txt"), includeMetadata: true, cancellation: CancellationFlag(), onProgress: { _ in })) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
            XCTAssertEqual(error.localizedDescription, "Permission denied")
        }
    }
}
#endif
