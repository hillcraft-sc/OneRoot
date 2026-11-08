import XCTest
@testable import OneRoot

final class FileUndoServiceTests: XCTestCase {
    private let service = FileUndoService()
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testRevertingAMoveMovesItBackAndReturnsTheInverse() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        let moved = try makeFile("new.txt")

        let result = await service.revert([.moved(from: original, to: moved)])

        XCTAssertNil(result.error)
        XCTAssertTrue(exists(original))
        XCTAssertFalse(exists(moved))
        XCTAssertEqual(result.reverted, [.moved(from: moved, to: original)])
    }

    func testRevertingTheInverseRedoesTheOriginalChange() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        let moved = try makeFile("new.txt")

        let undo = await service.revert([.moved(from: original, to: moved)])
        let redo = await service.revert(undo.reverted)

        XCTAssertNil(redo.error)
        XCTAssertTrue(exists(moved))
        XCTAssertFalse(exists(original))
    }

    func testRevertingACreateTrashesItAndRevertingThatPutsItBack() async throws {
        isolateTrashOnLinux()
        let created = try makeFile("copy.txt", contents: "keep me")

        let undo = await service.revert([.created(created)])

        XCTAssertNil(undo.error)
        XCTAssertFalse(exists(created), "undoing a copy moves the copy to Trash")
        guard case .trashed(let original, let trashedAt)? = undo.reverted.first else {
            return XCTFail("expected a .trashed change, got \(undo.reverted)")
        }
        XCTAssertEqual(original, created)
        XCTAssertTrue(exists(trashedAt))

        let redo = await service.revert(undo.reverted)

        XCTAssertNil(redo.error)
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "keep me")
        XCTAssertEqual(redo.reverted, [.created(created)])
    }

    func testRevertNeverOverwritesSomethingNowInTheOriginalSpot() async throws {
        let original = try makeFile("old.txt", contents: "newcomer")
        let moved = try makeFile("new.txt", contents: "moved")

        let result = await service.revert([.moved(from: original, to: moved)])

        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.reverted, [])
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "newcomer")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "moved")
    }

    func testRevertFailsCleanlyWhenTheItemIsGone() async {
        let original = tempDirectory.appendingPathComponent("old.txt")
        let moved = tempDirectory.appendingPathComponent("new.txt") // never created

        let result = await service.revert([.moved(from: original, to: moved)])

        guard case FileUndoError.missing? = result.error else {
            return XCTFail("expected .missing, got \(String(describing: result.error))")
        }
        XCTAssertFalse(exists(original))
    }

    func testBatchRevertsNewestFirstAndKeepsWhatSucceededBeforeAFailure() async throws {
        let firstOriginal = try makeFile("a.txt", contents: "blocker") // occupied, so this one fails
        let firstMoved = try makeFile("a-moved.txt")
        let secondOriginal = tempDirectory.appendingPathComponent("b.txt")
        let secondMoved = try makeFile("b-moved.txt")

        let result = await service.revert([
            .moved(from: firstOriginal, to: firstMoved),
            .moved(from: secondOriginal, to: secondMoved),
        ])

        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.reverted, [.moved(from: secondMoved, to: secondOriginal)])
        XCTAssertTrue(exists(secondOriginal))
        XCTAssertTrue(exists(firstMoved))
    }

    func testCaseOnlyRenameCanBeUndone() async throws {
        let renamed = try makeFile("Notes.txt")
        let original = tempDirectory.appendingPathComponent("notes.txt")

        let result = await service.revert([.moved(from: original, to: renamed)])

        XCTAssertNil(result.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path), ["notes.txt"])
    }
}
