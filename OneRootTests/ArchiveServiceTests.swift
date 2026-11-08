import XCTest
@testable import OneRoot

/// Exercises `ArchiveService` against `ditto` — the one engine guaranteed
/// present on any Mac running these tests, unlike p7zip.
final class ArchiveServiceTests: XCTestCase {
    private let service = ArchiveService()
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCompressSingleFileProducesZipNamedAfterTheFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let destination = try await service.compress(
            [fileURL], into: tempDirectory, baseName: "notes.txt", tool: Platform.defaultArchiveTool, format: .zip
        )

        XCTAssertEqual(destination.lastPathComponent, "notes.txt.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCompressMultipleItemsUsesGivenBaseName() async throws {
        let fileA = tempDirectory.appendingPathComponent("a.txt")
        let fileB = tempDirectory.appendingPathComponent("b.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        let destination = try await service.compress(
            [fileA, fileB], into: tempDirectory, baseName: "Archive", tool: Platform.defaultArchiveTool, format: .zip
        )

        XCTAssertEqual(destination.lastPathComponent, "Archive.zip")
    }

    func testCompressAutoNumbersOnCollision() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        try "existing".write(
            to: tempDirectory.appendingPathComponent("notes.txt.zip"), atomically: true, encoding: .utf8
        )

        let destination = try await service.compress(
            [fileURL], into: tempDirectory, baseName: "notes.txt", tool: Platform.defaultArchiveTool, format: .zip
        )

        XCTAssertEqual(destination.lastPathComponent, "notes.txt (2).zip")
    }

    func testExtractCreatesSubfolderNamedAfterTheArchiveContainingOriginalFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let archiveURL = try await service.compress(
            [fileURL], into: tempDirectory, baseName: "notes.txt", tool: Platform.defaultArchiveTool, format: .zip
        )
        // Extract into a clean subdirectory, not `tempDirectory` itself —
        // that still has the original "notes.txt" *file* sitting in it,
        // which would collide and force a "(2)" bump (covered separately
        // below), obscuring the plain, no-collision case this test wants.
        let extractionRoot = tempDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)

        let destination = try await service.extract(archiveURL, into: extractionRoot, tool: Platform.defaultArchiveTool)

        XCTAssertEqual(destination.lastPathComponent, "notes.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("notes.txt").path))
    }

    func testExtractAutoNumbersOnCollision() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let archiveURL = try await service.compress(
            [fileURL], into: tempDirectory, baseName: "notes.txt", tool: Platform.defaultArchiveTool, format: .zip
        )

        // `tempDirectory` still has the original "notes.txt" *file* sitting
        // in it (compress doesn't consume its sources) — extracting the
        // archive there collides with that name and should auto-number.
        let destination = try await service.extract(archiveURL, into: tempDirectory, tool: Platform.defaultArchiveTool)

        XCTAssertEqual(destination.lastPathComponent, "notes.txt (2)")
    }

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testExtractLeavesNoProgressEntryBehindOnceItFinishes() async throws {
        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let archiveURL = try await service.compress(
            [fileURL], into: tempDirectory, baseName: "notes.txt", tool: Platform.defaultArchiveTool, format: .zip
        )
        let extractionRoot = tempDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)

        let before = await FileOperationProgressCenter.shared.operations.count

        _ = try await service.extract(archiveURL, into: extractionRoot, tool: Platform.defaultArchiveTool)

        let after = await FileOperationProgressCenter.shared.operations.count
        XCTAssertEqual(after, before, "the progress popup's entry should be removed once extraction finishes")
    }
    #endif

    func testExtractRejectsAFormatTheToolCannotHandle() async {
        let imageURL = tempDirectory.appendingPathComponent("installer.dmg")
        try? "not an archive".write(to: imageURL, atomically: true, encoding: .utf8)

        do {
            _ = try await service.extract(imageURL, into: tempDirectory, tool: Platform.defaultArchiveTool)
            XCTFail("expected a disk image to be refused")
        } catch ArchiveError.unsupportedFormat(let ext, let tool) {
            XCTAssertEqual(ext, "dmg")
            XCTAssertEqual(tool, Platform.defaultArchiveTool)
        } catch {
            XCTFail("expected ArchiveError.unsupportedFormat, got \(error)")
        }
    }
}
