import XCTest
@testable import OneRoot

final class WorkspaceSearchTests: XCTestCase {
    private var base: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for folder in ["Docs", "Design", "Docs/Notes"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["Docs/plan.txt", "Docs/Notes/plan-notes.txt", "Design/plan.sketch", "Design/logo.png"] {
            try "x".write(to: base.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func url(_ path: String) -> URL { base.appendingPathComponent(path) }

    func testSearchRootsDropDuplicatesAndFoldersInsideOthers() {
        var criteria = SearchCriteria(root: url("Docs"))
        criteria.additionalRoots = [url("Design"), url("Docs/Notes"), url("Docs")]
        XCTAssertEqual(criteria.searchRoots.map(\.lastPathComponent), ["Docs", "Design"])
    }

    func testSearchesEveryFolderAndSkipsOnesThatAreGone() async throws {
        var criteria = SearchCriteria(root: url("Docs"))
        criteria.additionalRoots = [url("Design"), url("Unplugged")]
        criteria.pattern = "plan"
        var names: [String] = []
        for try await event in SearchService().search(criteria) {
            if case .matched(let result) = event { names.append(result.node.name) }
        }
        XCTAssertEqual(Set(names), ["plan.txt", "plan-notes.txt", "plan.sketch"])
    }

    func testTerminalCommandListsEveryFolder() {
        var criteria = SearchCriteria(root: url("Docs"))
        criteria.additionalRoots = [url("Design")]
        let command = SearchCommandLineBuilder().command(for: criteria)
        XCTAssertTrue(command.contains(url("Docs").path))
        XCTAssertTrue(command.contains(url("Design").path))
    }

    @MainActor
    func testAWorkspaceFilterBecomesASearchOfAllItsFolders() async {
        let viewModel = FileListViewModel(navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: .isolatedForTests())))
        await viewModel.navigate(to: url("Docs")).value
        viewModel.searchText = "plan"
        let workspace = Workspace(name: "Phoenix", folders: [url("Docs"), url("Design")])

        let criteria = viewModel.filterAsWorkspaceSearch(workspace)

        XCTAssertEqual(criteria?.searchRoots, [url("Docs"), url("Design")])
        XCTAssertEqual(criteria?.workspaceName, "Phoenix")
        XCTAssertEqual(criteria?.pattern, "plan")
    }
}
