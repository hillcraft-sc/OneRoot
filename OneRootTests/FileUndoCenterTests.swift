import XCTest
@testable import OneRoot

@MainActor
final class FileUndoCenterTests: XCTestCase {
    private var tempDirectory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var presentedErrors: [String] = []
    private var center: FileUndoCenter!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        suiteName = "FileUndoCenterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        presentedErrors = []
        center = FileUndoCenter(
            trashOriginService: TrashOriginService(defaults: defaults),
            presentError: { [unowned self] in self.presentedErrors.append($0) }
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func undo() async {
        center.undo()
        await center.pendingRevert?.value
    }

    private func redo() async {
        center.redo()
        await center.pendingRevert?.value
    }

    func testUndoAndRedoARename() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        let renamed = tempDirectory.appendingPathComponent("new.txt")
        try "x".write(to: renamed, atomically: true, encoding: .utf8)
        center.record([.moved(from: original, to: renamed)], actionName: "Rename")

        XCTAssertEqual(center.undoMenuItemTitle, "Undo Rename")

        await undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertEqual(center.redoMenuItemTitle, "Redo Rename")

        await redo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(center.canUndo, "redo leaves the change undoable again")
    }

    func testUndoingACopyTrashesTheCopyAndRedoPutsItBack() async throws {
        isolateTrashOnLinux()
        let source = tempDirectory.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let destDir = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let log = FileChangeLog()
        try await FileSystemService().copyItems([source], to: destDir, changeLog: log) { _ in .skip }
        center.record(log.changes, actionName: FileUndoCenter.actionName("Copy", items: [source]))

        XCTAssertEqual(center.undoMenuItemTitle, "Undo Copy of \u{201C}a.txt\u{201D}")

        await undo()
        let copy = destDir.appendingPathComponent("a.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "undoing a copy leaves the source alone")

        await redo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    func testUndoingATrashPutsItBackAndForgetsItsTrashOrigin() async throws {
        isolateTrashOnLinux()
        let original = tempDirectory.appendingPathComponent("a.txt")
        try "x".write(to: original, atomically: true, encoding: .utf8)
        let trashOrigins = TrashOriginService(defaults: defaults)
        let trashed = await FileSystemService().moveToTrash([original])
        let trashedAt = try XCTUnwrap(trashed.locations[original])
        trashOrigins.recordOrigin(trashedURL: trashedAt, originalURL: original)
        center.record([.trashed(original: original, trashedAt: trashedAt)], actionName: "Move to Trash")

        await undo()

        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertNil(trashOrigins.originalLocation(forTrashedURL: trashedAt))

        await redo()

        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        // Redo re-trashed it, so Restore should know where it came from again.
        let origins = defaults.dictionary(forKey: "com.oneroot.trashOrigins") as? [String: String] ?? [:]
        XCTAssertEqual(Array(origins.values), [original.path])
    }

    func testFailedUndoReportsTheErrorAndClearsTheStack() async throws {
        let original = tempDirectory.appendingPathComponent("old.txt")
        let renamed = tempDirectory.appendingPathComponent("new.txt") // gone before Undo runs
        center.record([.moved(from: original, to: renamed)], actionName: "Rename")

        await undo()

        XCTAssertEqual(presentedErrors.count, 1)
        XCTAssertFalse(center.canUndo)
        XCTAssertFalse(center.canRedo)
    }

    func testSomethingNewClearsRedo() async throws {
        let renamed = tempDirectory.appendingPathComponent("new.txt")
        try "x".write(to: renamed, atomically: true, encoding: .utf8)
        center.record([.moved(from: tempDirectory.appendingPathComponent("old.txt"), to: renamed)], actionName: "Rename")
        await undo()
        XCTAssertTrue(center.canRedo)

        center.record([.created(tempDirectory.appendingPathComponent("other.txt"))], actionName: "New Folder")

        XCTAssertFalse(center.canRedo)
        XCTAssertEqual(center.undoActionName, "New Folder")
    }

    func testKeepsTheLastHundredSteps() {
        for index in 0..<(FileUndoCenter.levelsOfUndo + 5) {
            center.record([.created(tempDirectory.appendingPathComponent("\(index)"))], actionName: "Step \(index)")
        }
        var count = 0
        while center.canUndo {
            center.undo()
            count += 1
        }
        XCTAssertEqual(count, FileUndoCenter.levelsOfUndo)
    }

    func testRecordingNothingAddsNoUndoStep() {
        center.record([], actionName: "Copy")

        XCTAssertFalse(center.canUndo)
    }

    func testActionNameWording() {
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        XCTAssertEqual(FileUndoCenter.actionName("Move", items: [a]), "Move of \u{201C}a.txt\u{201D}")
        XCTAssertEqual(FileUndoCenter.actionName("Move", items: [a, b]), "Move of 2 Items")
    }
}
