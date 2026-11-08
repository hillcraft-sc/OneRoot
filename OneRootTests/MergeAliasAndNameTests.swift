import XCTest
@testable import OneRoot

/// Merge as a conflict choice (#62), Make Alias Here (#68), and Copy Name
/// (#69). Replace/merge trashing goes to a fake Trash in a temp folder.
final class MergeAliasAndNameTests: XCTestCase {
    private var service = FileSystemService()
    private var tempDirectory: URL!
    private var destination: URL!
    private var fakeTrash: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        fakeTrash = tempDirectory.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        service.trashItem = FileSystemServiceTests.fakeTrashItem(into: fakeTrash)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @discardableResult
    private func write(_ text: String, _ path: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(path), encoding: .utf8)
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    /// Source folder "Project" with a.txt, b.txt, sub/c.txt; the existing
    /// dest/Project has b.txt (old), sub/d.txt, and keep.txt.
    private func makeFolders() throws -> URL {
        let source = tempDirectory.appendingPathComponent("src/Project", isDirectory: true)
        try write("new a", "a.txt", in: source)
        try write("new b", "b.txt", in: source)
        try write("new c", "sub/c.txt", in: source)
        let existing = destination.appendingPathComponent("Project", isDirectory: true)
        try write("old b", "b.txt", in: existing)
        try write("old d", "sub/d.txt", in: existing)
        try write("keep", "keep.txt", in: existing)
        return source
    }

    // MARK: Merge

    func testFolderConflictsOfferMergeButFilesAndPackagesDont() throws {
        let source = try makeFolders()
        let file = try write("x", "file.txt", in: tempDirectory.appendingPathComponent("src"))
        try write("y", "file.txt", in: destination)
        let app = tempDirectory.appendingPathComponent("src/Tool.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Tool.app"), withIntermediateDirectories: true)

        let conflicts = FileSystemService.conflicts(for: [source, file, app], in: destination)
        let byName = Dictionary(uniqueKeysWithValues: conflicts.map { ($0.name, $0) })

        XCTAssertEqual(byName["Project"]?.canMerge, true)
        XCTAssertEqual(byName["file.txt"]?.canMerge, false)
        #if os(macOS)
        XCTAssertEqual(byName["Tool.app"]?.canMerge, false, "a package is one document, never merged")
        #else
        XCTAssertEqual(byName["Tool.app"]?.canMerge, true, "no packages on Linux: just a folder")
        #endif
    }

    func testMergeAddsContentsAndAsksAboutCollisionsInside() async throws {
        let source = try makeFolders()
        var requests: [FileConflictRequest] = []

        try await service.copyItems([source], to: destination) { request in
            requests.append(request)
            if request.conflicts.map(\.name) == ["Project"] { return .all(.merge, for: request.conflicts) }
            // Inside: b.txt (file) and sub (folder).
            var answers: [URL: FileConflictResolution] = [:]
            for conflict in request.conflicts {
                answers[conflict.source] = conflict.canMerge ? .merge : .replace
            }
            return .resolve(answers)
        }

        XCTAssertEqual(requests.count, 2, "the folder, then one question for everything inside it")
        XCTAssertEqual(requests[1].conflicts.map(\.name).sorted(), ["b.txt", "sub"])
        XCTAssertEqual(requests[1].itemCount, 3)
        XCTAssertEqual(try read("Project/a.txt"), "new a")
        XCTAssertEqual(try read("Project/b.txt"), "new b")
        XCTAssertEqual(try read("Project/keep.txt"), "keep", "nothing already there is lost")
        XCTAssertEqual(try read("Project/sub/c.txt"), "new c")
        XCTAssertEqual(try read("Project/sub/d.txt"), "old d")
        XCTAssertEqual(try names(fakeTrash).count, 1, "only the replaced b.txt went to the Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a copy leaves the source alone")
    }

    func testMergeLogsOnlyWhatChangedSoUndoLeavesTheExistingFolder() async throws {
        let source = try makeFolders()
        let log = FileChangeLog()

        try await service.copyItems([source], to: destination, changeLog: log) { request in
            request.conflicts.map(\.name) == ["Project"] ? .all(.merge, for: request.conflicts) : .resolve([:])
        }

        let project = destination.appendingPathComponent("Project")
        XCTAssertEqual(log.changes, [.created(project.appendingPathComponent("a.txt"))],
                       "b.txt and sub were skipped; the existing folder itself isn't a change")
    }

    func testMoveMergeTrashesTheEmptiedSourceFolderLast() async throws {
        let source = tempDirectory.appendingPathComponent("src/Project", isDirectory: true)
        try write("new a", "a.txt", in: source)
        try write("view settings", ".DS_Store", in: source)
        try write("keep", "keep.txt", in: destination.appendingPathComponent("Project"))
        let log = FileChangeLog()

        try await service.moveItems([source], to: destination, changeLog: log) { .all(.merge, for: $0.conflicts) }

        XCTAssertEqual(try read("Project/a.txt"), "new a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "the emptied folder went to the Trash")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Project/.DS_Store").path),
                       ".DS_Store isn't merged")
        XCTAssertEqual(log.changes.count, 2)
        XCTAssertEqual(log.changes[0], .moved(from: source.appendingPathComponent("a.txt"), to: destination.appendingPathComponent("Project/a.txt")))
        guard case .trashed(let original, _) = log.changes[1] else { return XCTFail("expected the source folder's trashing last") }
        XCTAssertEqual(original, source, "Undo puts the folder back first, then moves the files into it")
    }

    func testMoveMergeLeavesTheSourceFolderWhenSomethingWasSkipped() async throws {
        let source = try makeFolders()

        try await service.moveItems([source], to: destination) { request in
            request.conflicts.map(\.name) == ["Project"] ? .all(.merge, for: request.conflicts) : .resolve([:])
        }

        XCTAssertEqual(try names(source), ["b.txt", "sub"], "skipped items stay where they were")
        XCTAssertTrue(try names(fakeTrash).isEmpty)
    }

    func testCancelInsideAMergeStops() async throws {
        let source = try makeFolders()

        do {
            try await service.copyItems([source], to: destination) { request in
                request.conflicts.map(\.name) == ["Project"] ? .all(.merge, for: request.conflicts) : .cancel
            }
            XCTFail("expected CancellationError")
        } catch is CancellationError {}

        XCTAssertEqual(try names(destination.appendingPathComponent("Project")), ["b.txt", "keep.txt", "sub"], "nothing copied")
    }

    func testMergeForSomethingThatIsntTwoFoldersSkips() async throws {
        let file = try write("new", "a.txt", in: tempDirectory.appendingPathComponent("src"))
        try write("old", "a.txt", in: destination)

        try await service.copyItems([file], to: destination) { .all(.merge, for: $0.conflicts) }

        XCTAssertEqual(try read("a.txt"), "old")
    }

    // MARK: Make Alias

    #if os(macOS) // macOS behavior; Linux gets its own in phase 4 (#81)
    func testMakeAliasesNamesThemLikeFinderAndTheyResolve() async throws {
        let target = try write("x", "report.pdf", in: tempDirectory.appendingPathComponent("src"))

        let first = try await service.makeAliases(to: [target], in: destination)
        let second = try await service.makeAliases(to: [target], in: destination)

        XCTAssertEqual(first.map(\.lastPathComponent), ["report.pdf alias"])
        XCTAssertEqual(second.map(\.lastPathComponent), ["report.pdf alias 2"])
        let resolved = try URL(resolvingAliasFileAt: first[0])
        XCTAssertEqual(resolved.standardizedFileURL.resolvingSymlinksInPath(), target.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(try first[0].resourceValues(forKeys: [.isAliasFileKey]).isAliasFile, true)
    }
    #endif

    func testMakeAliasToAMissingItemFails() async {
        let missing = tempDirectory.appendingPathComponent("gone.txt")
        do {
            _ = try await service.makeAliases(to: [missing], in: destination)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("gone.txt"))
        }
    }

    // MARK: Copy Name

    private func node(_ name: String, directory: Bool = false, package: Bool = false) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: directory, isPackage: package, size: nil, modificationDate: nil, kind: nil)
    }

    func testCopyNameWithAndWithoutExtension() {
        let nodes = [node("photo.final.jpg"), node("v1.2", directory: true), node("Mail.app", directory: true, package: true), node(".zshrc"), node("README")]

        XCTAssertEqual(CopyableName.text(for: nodes, includeExtension: true), "photo.final.jpg\nv1.2\nMail.app\n.zshrc\nREADME")
        XCTAssertEqual(CopyableName.text(for: nodes, includeExtension: false), "photo.final\nv1.2\nMail\n.zshrc\nREADME")
    }

    func testWithoutExtensionIsOfferedOnlyWhenItChangesSomething() {
        XCTAssertTrue(CopyableName.hasStrippableExtension(node("a.txt")))
        XCTAssertTrue(CopyableName.hasStrippableExtension(node("Mail.app", directory: true, package: true)))
        XCTAssertFalse(CopyableName.hasStrippableExtension(node("v1.2", directory: true)))
        XCTAssertFalse(CopyableName.hasStrippableExtension(node(".zshrc")))
        XCTAssertFalse(CopyableName.hasStrippableExtension(node("README")))
    }
}
