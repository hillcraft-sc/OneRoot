import XCTest
@testable import OneRoot

/// Names Windows-style destinations reject (#70).
final class NameCompatibilityTests: XCTestCase {
    private var service = FileSystemService()
    private var tempDirectory: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        let trash = tempDirectory.appendingPathComponent("trash", isDirectory: true)
        for folder in [destination!, trash] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        service.trashItem = FileSystemServiceTests.fakeTrashItem(into: trash)
        service.queuesTransfers = { false }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @discardableResult
    private func write(_ path: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent("src").appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: url)
        return url
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: Rules

    func testFixedNames() {
        XCTAssertNil(NameCompatibility.fixedName(for: "report.pdf"))
        XCTAssertNil(NameCompatibility.fixedName(for: "Ünïcödé ok 😀.txt"))
        XCTAssertEqual(NameCompatibility.fixedName(for: "What? Why*.txt"), "What_ Why_.txt")
        XCTAssertEqual(NameCompatibility.fixedName(for: "a:b|c\"d<e>f\\g"), "a_b_c_d_e_f_g")
        XCTAssertEqual(NameCompatibility.fixedName(for: "trailing. "), "trailing")
        XCTAssertEqual(NameCompatibility.fixedName(for: "..."), "_")
        XCTAssertEqual(NameCompatibility.fixedName(for: "con.txt"), "con_.txt")
        XCTAssertEqual(NameCompatibility.fixedName(for: "LPT1"), "LPT1_")
        XCTAssertNil(NameCompatibility.fixedName(for: "CONSOLE.txt"), "only the exact device names")
        XCTAssertEqual(NameCompatibility.fixedName(for: "tab\there"), "tab_here")
    }

    func testProblemsLookInsideFoldersAndAvoidCollisions() throws {
        try write("Top?/inner*.txt")
        try write("Top?/fine.txt")
        try write("Top?/a?.txt")
        try write("Top?/a*.txt")
        try write("ok/also ok.txt")
        let top = tempDirectory.appendingPathComponent("src/Top?")
        let ok = tempDirectory.appendingPathComponent("src/ok")

        let (fixes, truncated) = NameCompatibility.problems(in: [top, ok])

        XCTAssertFalse(truncated)
        let byOld = Dictionary(uniqueKeysWithValues: fixes.map { ($0.oldName, $0.newName) })
        XCTAssertEqual(byOld["Top?"], "Top_")
        XCTAssertEqual(byOld["inner*.txt"], "inner_.txt")
        XCTAssertEqual(Set([byOld["a?.txt"], byOld["a*.txt"]]), ["a_.txt", "a_ (2).txt"], "two bad names never end up the same")
        XCTAssertEqual(fixes.count, 4)
    }

    func testMacDisksDontRestrictNames() {
        XCTAssertFalse(NameCompatibility.restrictsNames(at: tempDirectory))
    }

    func testFoldersContainingStaysInsideWhatWasChosen() {
        let top = URL(fileURLWithPath: "/a/top")
        let folders = FileSystemService.foldersContaining([URL(fileURLWithPath: "/a/top/b/c/bad?.txt"), URL(fileURLWithPath: "/a/top")], within: [top])
        XCTAssertEqual(Set(folders.map(\.standardizedFileURL.path)), ["/a/top", "/a/top/b", "/a/top/b/c"])
    }

    // MARK: Copying with fixes

    func testCopyRenamesInsideFoldersAndKeepsTheRest() async throws {
        try write("Project?/notes*.txt")
        try write("Project?/sub/clean.txt")
        try write("Project?/sub/bad|name.txt")
        let source = tempDirectory.appendingPathComponent("src/Project?")
        let fixes = NameCompatibility.problems(in: [source]).fixes
        let log = FileChangeLog()

        try await service.copyItems([source], to: destination, changeLog: log, resolveConflicts: { _ in .cancel },
                                    nameFixes: Dictionary(uniqueKeysWithValues: fixes.map { ($0.source, $0.newName) }))

        XCTAssertEqual(try names(destination), ["Project_"])
        XCTAssertEqual(try names(destination.appendingPathComponent("Project_")), ["notes_.txt", "sub"])
        XCTAssertEqual(try names(destination.appendingPathComponent("Project_/sub")), ["bad_name.txt", "clean.txt"])
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Project_/sub/bad_name.txt"), encoding: .utf8), "Project?/sub/bad|name.txt")
        guard case .created(let made) = log.changes.first else { return XCTFail("expected the made folder first: \(log.changes)") }
        XCTAssertEqual(made.standardizedFileURL.path, destination.appendingPathComponent("Project_").standardizedFileURL.path, "the made folder is undone last")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a copy leaves the original")
    }

    func testSkippedItemsAreLeftOut() async throws {
        try write("Folder/keep.txt")
        let bad = try write("Folder/skip?.txt")
        let loose = try write("loose*.txt")
        let fine = try write("fine.txt")

        try await service.copyItems([tempDirectory.appendingPathComponent("src/Folder"), loose, fine], to: destination,
                                    resolveConflicts: { _ in .cancel }, skipping: [bad, loose])

        XCTAssertEqual(try names(destination), ["Folder", "fine.txt"])
        XCTAssertEqual(try names(destination.appendingPathComponent("Folder")), ["keep.txt"])
    }

    func testMoveWithFixesLeavesSkippedItemsAndTrashesEmptiedFolders() async throws {
        try write("Moving/a?.txt")
        try write("Moving/b.txt")
        let source = tempDirectory.appendingPathComponent("src/Moving")
        let bad = source.appendingPathComponent("a?.txt")

        try await service.moveItems([source], to: destination, resolveConflicts: { _ in .cancel }, nameFixes: [bad: "a_.txt"])

        XCTAssertEqual(try names(destination.appendingPathComponent("Moving")), ["a_.txt", "b.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "emptied, so it went to the Trash")
    }
}
