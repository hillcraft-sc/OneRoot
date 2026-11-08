import XCTest
@testable import OneRoot

final class CloudStorageLocationsServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Real machines (including this one) can have iCloud Drive enabled,
    /// which would otherwise leak into every test below via the default
    /// `iCloudDriveURL` — point it at something that doesn't exist unless a
    /// test specifically wants to verify the "present" case.
    private var noICloudDrive: URL { tempDirectory.appendingPathComponent("no-icloud-drive") }

    func testDiscoversSubfoldersOnly() throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Nextcloud-account"), withIntermediateDirectories: true)
        try "x".write(to: tempDirectory.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        let service = CloudStorageLocationsService(cloudStorageDirectory: tempDirectory, iCloudDriveURL: noICloudDrive)

        let discovered = service.discover()

        XCTAssertEqual(discovered.map(\.lastPathComponent), ["Nextcloud-account"])
    }

    func testMissingDirectoryReturnsEmptyWithoutThrowing() {
        let missingDirectory = tempDirectory.appendingPathComponent("does-not-exist")
        let service = CloudStorageLocationsService(cloudStorageDirectory: missingDirectory, iCloudDriveURL: noICloudDrive)

        XCTAssertTrue(service.discover().isEmpty)
    }

    func testIncludesICloudDriveWhenPresent() throws {
        let iCloudDriveURL = tempDirectory.appendingPathComponent("com~apple~CloudDocs")
        try FileManager.default.createDirectory(at: iCloudDriveURL, withIntermediateDirectories: true)
        let missingCloudStorageDirectory = tempDirectory.appendingPathComponent("CloudStorage")
        let service = CloudStorageLocationsService(cloudStorageDirectory: missingCloudStorageDirectory, iCloudDriveURL: iCloudDriveURL)

        XCTAssertEqual(service.discover(), [iCloudDriveURL])
    }

    func testOmitsICloudDriveWhenNotPresent() {
        let missingCloudStorageDirectory = tempDirectory.appendingPathComponent("CloudStorage")
        let service = CloudStorageLocationsService(cloudStorageDirectory: missingCloudStorageDirectory, iCloudDriveURL: noICloudDrive)

        XCTAssertTrue(service.discover().isEmpty)
    }
}
