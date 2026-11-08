import XCTest
@testable import OneRoot

final class FullDiskAccessCheckerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testReadableProbeFileReportsAccessGranted() throws {
        let probeFile = tempDirectory.appendingPathComponent("readable.db")
        try "probe".write(to: probeFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(FullDiskAccessChecker.hasAccess(probingPath: probeFile.path))
    }

    func testMissingProbeFileReportsAccessDenied() {
        let missingFile = tempDirectory.appendingPathComponent("does-not-exist.db")

        XCTAssertFalse(FullDiskAccessChecker.hasAccess(probingPath: missingFile.path))
    }

    func testUnreadableProbeFileReportsAccessDenied() throws {
        let unreadableFile = tempDirectory.appendingPathComponent("locked.db")
        try "probe".write(to: unreadableFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableFile.path)

        XCTAssertFalse(FullDiskAccessChecker.hasAccess(probingPath: unreadableFile.path))
    }
}
