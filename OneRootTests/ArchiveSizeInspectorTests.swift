import XCTest
@testable import OneRoot

final class ArchiveSizeInspectorTests: XCTestCase {
    private let inspector = ArchiveSizeInspector()
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testParseTotalBytesReadsTheSummaryLine() {
        let listing = """
        Archive:  notes.zip
          Length      Date    Time    Name
        ---------  ---------- -----   ----
                6  07-26-2026 16:56   notes.txt
                0  07-26-2026 16:56   __MACOSX/
              163  07-26-2026 16:56   __MACOSX/._notes.txt
        ---------                     -------
              169                     3 files
        """

        XCTAssertEqual(ArchiveSizeInspector.parseTotalBytes(fromUnzipListing: listing), 169)
    }

    func testParseTotalBytesReturnsNilForUnrecognizedOutput() {
        XCTAssertNil(ArchiveSizeInspector.parseTotalBytes(fromUnzipListing: ""))
        XCTAssertNil(ArchiveSizeInspector.parseTotalBytes(fromUnzipListing: "not a listing at all"))
    }

    func testTotalUncompressedSizeOfARealZip() async throws {
        try skipOnLinuxUntilPhase4("Archive inspection")
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8) // 11 bytes
        let zipURL = tempDirectory.appendingPathComponent("notes.zip")
        let archiveService = ArchiveService()
        _ = try await archiveService.compress([fileURL], into: tempDirectory, baseName: "notes", tool: .appleDitto, format: .zip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        let total = await inspector.totalUncompressedSize(of: zipURL)

        // The zip also carries ditto's __MACOSX/._notes.txt AppleDouble
        // sidecar, so this is "at least the real file's size," not an
        // exact match.
        XCTAssertNotNil(total)
        XCTAssertGreaterThanOrEqual(total ?? 0, 11)
    }

    func testTotalUncompressedSizeOfANonZipIsNil() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let total = await inspector.totalUncompressedSize(of: fileURL)

        XCTAssertNil(total)
    }
}
