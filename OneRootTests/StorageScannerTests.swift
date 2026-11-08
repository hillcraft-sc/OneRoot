import XCTest
@testable import OneRoot

final class StorageScannerTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Unlock anything a test locked, then clean up.
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator { chmod(url.path, 0o755) }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func file(_ path: String, bytes: Int, modifiedDaysAgo days: Double = 0) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86_400)], ofItemAtPath: url.path)
        return url
    }

    private func scan() async throws -> StorageReport {
        var last: StorageReport?
        for try await report in StorageScanner().scan(root, now: now) { last = report }
        return try XCTUnwrap(last)
    }

    func testTotalsAndTheFoldersOwnItemsLargestFirst() async throws {
        try file("Photos/a.jpg", bytes: 3000)
        try file("Photos/2025/b.png", bytes: 2000)
        try file("notes.txt", bytes: 500)
        try file("Music/song.mp3", bytes: 4000)

        let report = try await scan()

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.totalSize, 9500)
        XCTAssertEqual(report.fileCount, 4)
        XCTAssertEqual(report.folderCount, 3)
        XCTAssertEqual(report.children.map(\.name), ["Photos", "Music", "notes.txt"])
        XCTAssertEqual(report.children.map(\.size), [5000, 4000, 500])
        XCTAssertEqual(report.children[0].fileCount, 2)
        XCTAssertFalse(report.children[2].isDirectory)
    }

    func testKindsOfFile() async throws {
        try file("a.jpg", bytes: 100)
        try file("b.mov", bytes: 200)
        try file("c.mp3", bytes: 300)
        try file("d.pdf", bytes: 400)
        try file("e.zip", bytes: 500)
        try file("f.swift", bytes: 600)
        try file("g.unknownthing", bytes: 700)

        let report = try await scan()

        XCTAssertEqual(report.categories[.images]?.size, 100)
        XCTAssertEqual(report.categories[.video]?.size, 200)
        XCTAssertEqual(report.categories[.audio]?.size, 300)
        XCTAssertEqual(report.categories[.documents]?.size, 400)
        XCTAssertEqual(report.categories[.archives]?.size, 500)
        XCTAssertEqual(report.categories[.code]?.size, 600)
        XCTAssertEqual(report.categories[.other]?.size, 700)
    }

    func testAgesFromLastModified() async throws {
        try file("new.txt", bytes: 10, modifiedDaysAgo: 1)
        try file("month.txt", bytes: 20, modifiedDaysAgo: 20)
        try file("year.txt", bytes: 30, modifiedDaysAgo: 200)
        try file("old.txt", bytes: 40, modifiedDaysAgo: 800)

        let report = try await scan()

        XCTAssertEqual(report.ages[.thisWeek]?.size, 10)
        XCTAssertEqual(report.ages[.thisMonth]?.size, 20)
        XCTAssertEqual(report.ages[.thisYear]?.size, 30)
        XCTAssertEqual(report.ages[.older]?.size, 40)
    }

    func testTagsAndUntagged() async throws {
        let red = try file("red.txt", bytes: 10)
        try file("plain.txt", bytes: 20)
        try TagService().setTags(["Red", "Work"], on: red)
        // Reading back first: the tag write can take a moment to show up
        // in a directory listing otherwise.
        XCTAssertEqual(try TagService().tags(of: red), ["Red", "Work"])

        let report = try await scan()

        XCTAssertEqual(report.tags["Red"]?.size, 10)
        XCTAssertEqual(report.tags["Work"]?.size, 10)
        XCTAssertEqual(report.untagged.size, 20)
        XCTAssertFalse(report.hasCloudItems)
        XCTAssertEqual(report.cloud[.notInCloud]?.count, 2)
    }

    func testAPackageCountsAsOneItemOfItsKind() async throws {
        try file("Tool.app/Contents/MacOS/Tool", bytes: 1000)
        try file("Tool.app/Contents/Resources/icon.png", bytes: 500)

        let report = try await scan()

        let apps = try XCTUnwrap(report.categories[.apps])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.size, 1500)
        XCTAssertEqual(apps.largest.map(\.url.lastPathComponent), ["Tool.app"])
        XCTAssertNil(report.categories[.images], "an app's own images aren't counted as images")
        XCTAssertEqual(report.fileCount, 2)
    }

    func testSymbolicLinksAreNotFollowed() async throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(count: 5000).write(to: outside.appendingPathComponent("big.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        try file("real.txt", bytes: 10)

        let report = try await scan()

        XCTAssertEqual(report.totalSize, 10)
    }

    func testUnreadableFoldersAreCountedAndSkipped() async throws {
        try file("open/a.txt", bytes: 10)
        try file("locked/b.txt", bytes: 20)
        chmod(root.appendingPathComponent("locked").path, 0)

        let report = try await scan()

        XCTAssertEqual(report.totalSize, 10)
        XCTAssertEqual(report.unreadableCount, 1)
    }

    func testLargestFilesPerGroupAreKeptInOrderAndCapped() {
        var bucket = StorageBucket()
        for size in (1...30).shuffled() {
            bucket.add(StorageFile(url: URL(fileURLWithPath: "/f\(size)"), size: Int64(size)))
        }
        XCTAssertEqual(bucket.count, 30)
        XCTAssertEqual(bucket.size, (1...30).reduce(0, +))
        XCTAssertEqual(bucket.largest.count, StorageBucket.largestLimit)
        XCTAssertEqual(bucket.largest.first?.size, 30)
        XCTAssertEqual(bucket.largest.map(\.size), bucket.largest.map(\.size).sorted(by: >))
    }

    func testAMissingFolderFails() async {
        do {
            for try await _ in StorageScanner().scan(root.appendingPathComponent("nope")) {}
            XCTFail("Expected an error")
        } catch {}
    }
}
