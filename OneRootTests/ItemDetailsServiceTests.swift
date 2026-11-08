import XCTest
@testable import OneRoot

final class ItemDetailsServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testFolderItemCountSkipsHiddenItems() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDirectory.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Sub"), withIntermediateDirectories: true)

        let details = await ItemDetailsService().details(for: tempDirectory, isDirectory: true)

        XCTAssertEqual(details.itemCount, 2)
    }

    func testFilesHaveNoItemCount() async throws {
        let file = tempDirectory.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let details = await ItemDetailsService().details(for: file, isDirectory: false)

        XCTAssertNil(details.itemCount)
    }

    func testMissingItemYieldsNoDetailsRatherThanFailing() async {
        let details = await ItemDetailsService().details(for: tempDirectory.appendingPathComponent("gone"), isDirectory: true)

        XCTAssertEqual(details, ItemDetails())
    }

    func testDurationFormatting() {
        XCTAssertEqual(ItemDetailsService.formatDuration(42), "0:42")
        XCTAssertEqual(ItemDetailsService.formatDuration(185.4), "3:05")
        XCTAssertEqual(ItemDetailsService.formatDuration(3723), "1:02:03")
    }
}

final class ItemDetailsGetInfoTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testOwnershipPermissionsAndSizeOnDisk() async throws {
        let file = tempDirectory.appendingPathComponent("a.txt")
        try String(repeating: "x", count: 10).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)

        let details = await ItemDetailsService().details(for: file, isDirectory: false)

        XCTAssertEqual(details.owner, NSUserName())
        XCTAssertNotNil(details.group)
        XCTAssertEqual(details.posixPermissions, 0o640)
        XCTAssertFalse(details.isLocked)
        XCTAssertGreaterThanOrEqual(details.sizeOnDisk ?? 0, 10, "allocated in whole blocks")
        XCTAssertNil(details.cloud, "a local temp file isn't a cloud item")
    }

    func testLockedFilesAreReported() async throws {
        let file = tempDirectory.appendingPathComponent("locked.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path) }

        let details = await ItemDetailsService().details(for: file, isDirectory: false)

        XCTAssertTrue(details.isLocked)
    }

    func testSymbolicLinkReportsItsDestination() async throws {
        let target = tempDirectory.appendingPathComponent("target.txt")
        try "x".write(to: target, atomically: true, encoding: .utf8)
        let link = tempDirectory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let details = await ItemDetailsService().details(for: link, isDirectory: false)

        XCTAssertEqual(details.linkDestination, target.path)
    }

    func testAppVersionFallsBackToItsBundle() async throws {
        let app = tempDirectory.appendingPathComponent("Test.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "4.2.1", "CFBundleIdentifier": "com.example.test"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let details = await ItemDetailsService().details(for: app, isDirectory: false)

        XCTAssertEqual(details.version, "4.2.1")
    }

    func testAccessWordsMatchGetInfo() {
        XCTAssertEqual(ItemDetailsService.access(0o754, for: .owner), "Read & Write")
        XCTAssertEqual(ItemDetailsService.access(0o754, for: .group), "Read only")
        XCTAssertEqual(ItemDetailsService.access(0o754, for: .everyone), "Read only")
        XCTAssertEqual(ItemDetailsService.access(0o700, for: .everyone), "No Access")
        XCTAssertEqual(ItemDetailsService.access(0o020, for: .group), "Write only")
    }

    func testDownloadSourcesShowTheSite() {
        XCTAssertEqual(ItemDetailsService.displaySource("https://www.example.com/files/a.zip"), "example.com")
        XCTAssertEqual(ItemDetailsService.displaySource("https://downloads.example.org/x"), "downloads.example.org")
        XCTAssertEqual(ItemDetailsService.displaySource("not a url"), "not a url")
    }
}
