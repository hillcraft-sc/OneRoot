import XCTest
@testable import OneRoot

/// Show All Files in Subfolders (#66).
@MainActor
final class FlatViewTests: XCTestCase {
    private var root: URL!
    private var viewModel: FileListViewModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for path in ["top.txt", "a/one.txt", "a/b/two.txt", "a/b/c/three.txt", ".hidden.txt", "Tool.app/Contents/inside.txt"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        viewModel = FileListViewModel(
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testListsEveryFileButNotFoldersOrInsidePackages() async throws {
        await viewModel.navigate(to: root).value
        try XCTSkipIf(viewModel.showHiddenFiles, "the developer's own Show Hidden Files is on")

        await viewModel.setShowsAllFilesInSubfolders(true)?.value

        #if os(macOS)
        XCTAssertEqual(Set(viewModel.items.map(\.name)), ["top.txt", "one.txt", "two.txt", "three.txt", "Tool.app"])
        #else // no packages on Linux: Tool.app is a folder, so its file is listed and it isn't
        XCTAssertEqual(Set(viewModel.items.map(\.name)), ["top.txt", "one.txt", "two.txt", "three.txt", "inside.txt"])
        #endif
        XCTAssertTrue(viewModel.displayedColumns.contains(.location), "Where shows which folder each file is in")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.flatViewIsTruncated)
    }

    func testTurningItOffOrLeavingTheFolderGoesBack() async throws {
        await viewModel.navigate(to: root).value
        await viewModel.setShowsAllFilesInSubfolders(true)?.value

        await viewModel.setShowsAllFilesInSubfolders(false)?.value
        XCTAssertEqual(Set(viewModel.items.map(\.name)).intersection(["a", "top.txt"]), ["a", "top.txt"])
        XCTAssertFalse(viewModel.items.contains { $0.name == "three.txt" })

        await viewModel.setShowsAllFilesInSubfolders(true)?.value
        await viewModel.navigate(to: root.appendingPathComponent("a")).value
        XCTAssertFalse(viewModel.showsAllFilesInSubfolders, "another folder starts as a normal listing")
        XCTAssertEqual(Set(viewModel.items.map(\.name)), ["one.txt", "b"])
    }

    func testTheWalkStopsAtTheLimit() async throws {
        let service = FileSystemService()
        let collected = Collected()

        let truncated = try await service.listAllFiles(under: root, includeHidden: true, limit: 3) { batch in
            await collected.add(batch.count)
        }

        XCTAssertTrue(truncated)
        let total = await collected.total
        XCTAssertEqual(total, 3)
    }

    func testHiddenFilesFollowTheSetting() async throws {
        let service = FileSystemService()
        let names = Names()
        _ = try await service.listAllFiles(under: root, includeHidden: true) { batch in await names.add(batch.map(\.name)) }
        let all = await names.all
        XCTAssertTrue(all.contains(".hidden.txt"))
    }
}

private actor Collected {
    var total = 0
    func add(_ count: Int) { total += count }
}

private actor Names {
    var all: [String] = []
    func add(_ names: [String]) { all += names }
}

/// Duplicate (⌘D).
@MainActor
final class DuplicateCommandTests: XCTestCase {
    func testDuplicateMakesNumberedCopiesBesideEachAndSelectsThem() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("report.pdf"))
        try Data("y".utf8).write(to: root.appendingPathComponent("Folder/inside.txt"))
        let undo = FileUndoCenter(presentError: { _ in })
        let viewModel = FileListViewModel(
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)),
            undoCenter: undo
        )
        await viewModel.navigate(to: root).value
        let selection = viewModel.items.filter { ["report.pdf", "Folder"].contains($0.name) }
        let before = viewModel.selectionRequest

        await viewModel.duplicate(selection)?.value

        let names = Set(viewModel.items.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["report.pdf", "report (2).pdf", "Folder", "Folder (2)"]), "\(names)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Folder (2)/inside.txt").path))
        XCTAssertEqual(viewModel.selectionRequest, before + 1)
        XCTAssertEqual(Set(viewModel.requestedSelection.map(\.lastPathComponent)), ["report (2).pdf", "Folder (2)"])
        XCTAssertEqual(undo.undoActionName, "Duplicate of 2 Items")
    }
}
