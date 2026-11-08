import XCTest
@testable import OneRoot

@MainActor
final class FileChooserViewModelTests: XCTestCase {
    private var root: URL!
    private var projects: URL!
    private var phoenix: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        projects = root.appendingPathComponent("Projects", isDirectory: true)
        phoenix = projects.appendingPathComponent("Phoenix", isDirectory: true)
        try FileManager.default.createDirectory(at: phoenix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden", isDirectory: true), withIntermediateDirectories: true)
        try "x".write(to: projects.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeViewModel(at url: URL? = nil, options: FileChooserViewModel.Options = .init(), showsHidden: Bool = false) async -> FileChooserViewModel {
        let viewModel = FileChooserViewModel(startingAt: url ?? root, options: options, showsHidden: showsHidden, homeURL: root)
        await viewModel.start(shortcuts: { [] })
        return viewModel
    }

    private func names(_ viewModel: FileChooserViewModel) -> [String] {
        viewModel.entries.map(\.name).sorted()
    }

    // MARK: Listing

    func testFolderPickerListsFoldersOnly() async {
        let viewModel = await makeViewModel(at: projects)

        XCTAssertEqual(names(viewModel), ["Phoenix"])
    }

    func testFilePickerListsFilesOfAllowedTypes() async throws {
        try "x".write(to: projects.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)
        let viewModel = await makeViewModel(at: projects, options: .init(canChooseFiles: true, canChooseDirectories: false, allowsFile: { $0.pathExtension == "txt" }))

        XCTAssertEqual(names(viewModel), ["Phoenix", "notes.txt"])
    }

    func testHiddenFoldersShowOnlyWhenAsked() async {
        let viewModel = await makeViewModel()
        XCTAssertFalse(names(viewModel).contains(".hidden"))

        await viewModel.setShowsHidden(true)

        XCTAssertTrue(names(viewModel).contains(".hidden"))
        XCTAssertTrue(viewModel.treeRows.contains { $0.name == ".hidden" }, "the tree shows them too")
    }

    // MARK: Navigation

    func testBackForwardAndUp() async {
        let viewModel = await makeViewModel()

        await viewModel.navigate(to: projects)
        await viewModel.navigate(to: phoenix)
        await viewModel.goBack()
        XCTAssertEqual(viewModel.currentDirectory, projects.standardizedFileURL)
        await viewModel.goForward()
        XCTAssertEqual(viewModel.currentDirectory, phoenix.standardizedFileURL)
        await viewModel.goUp()
        XCTAssertEqual(viewModel.currentDirectory, projects.standardizedFileURL)
        XCTAssertFalse(viewModel.canGoForward, "going up is a new step, like the main window")
    }

    func testOpeningAFolderGoesIntoIt() async {
        let viewModel = await makeViewModel(at: projects)

        let chosen = await viewModel.open(phoenix.standardizedFileURL)

        XCTAssertNil(chosen)
        XCTAssertEqual(viewModel.currentDirectory, phoenix.standardizedFileURL)
    }

    func testTreeRevealsTheCurrentFolder() async {
        let viewModel = await makeViewModel(at: phoenix)

        XCTAssertEqual(viewModel.treeRows.map(\.name).first, root.lastPathComponent, "rooted at Home")
        XCTAssertTrue(viewModel.treeRows.contains { $0.url == phoenix.standardizedFileURL && $0.depth == 2 })
    }

    // MARK: Path field

    func testPastedPathNavigates() async {
        let viewModel = await makeViewModel()

        viewModel.pathText = phoenix.path
        await viewModel.submitPath()

        XCTAssertEqual(viewModel.currentDirectory, phoenix.standardizedFileURL)
        XCTAssertNil(viewModel.pathError)
    }

    func testMissingPathIsFlaggedWithoutMoving() async {
        let viewModel = await makeViewModel()

        viewModel.pathText = root.appendingPathComponent("Nope").path
        await viewModel.submitPath()

        XCTAssertEqual(viewModel.currentDirectory, root.standardizedFileURL)
        XCTAssertNotNil(viewModel.pathError)
    }

    func testPastedFilePathSelectsTheFileWhenFilesCanBeChosen() async {
        let viewModel = await makeViewModel(options: .init(canChooseFiles: true, canChooseDirectories: false))
        let notes = projects.appendingPathComponent("notes.txt").standardizedFileURL

        viewModel.pathText = notes.path
        await viewModel.submitPath()

        XCTAssertEqual(viewModel.currentDirectory, projects.standardizedFileURL)
        XCTAssertEqual(viewModel.chosenURLs.map(\.standardizedFileURL.path), [notes.path])
    }

    func testSuggestionsMatchTheTypedPrefix() async {
        let viewModel = await makeViewModel()

        viewModel.pathText = projects.path + "/Ph"
        await viewModel.updateSuggestions()

        XCTAssertEqual(viewModel.suggestions, ["Phoenix"])
    }

    // MARK: Choosing

    func testChoosingWithNothingSelectedPicksTheCurrentFolder() async {
        let viewModel = await makeViewModel(at: projects)

        XCTAssertEqual(viewModel.chosenURLs, [projects.standardizedFileURL])
    }

    func testSingleSelectionKeepsOnlyTheNewestItem() async throws {
        let other = root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let viewModel = await makeViewModel()
        let projectsURL = try XCTUnwrap(viewModel.entries.first { $0.name == "Projects" }?.url)
        let otherURL = try XCTUnwrap(viewModel.entries.first { $0.name == "Other" }?.url)

        viewModel.setSelection([projectsURL])
        viewModel.setSelection([projectsURL, otherURL])

        XCTAssertEqual(viewModel.selection, [otherURL])
    }

    func testMultipleSelectionChoosesEveryFolder() async throws {
        let other = root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let viewModel = await makeViewModel(options: .init(allowsMultipleSelection: true))
        let picked = Set(viewModel.entries.filter { ["Projects", "Other"].contains($0.name) }.map(\.url))

        viewModel.setSelection(picked)

        XCTAssertEqual(Set(viewModel.chosenURLs), picked)
    }

    func testAFolderCantBeChosenWhenPickingFiles() async throws {
        let viewModel = await makeViewModel(at: projects, options: .init(canChooseFiles: true, canChooseDirectories: false))
        let folder = try XCTUnwrap(viewModel.entries.first { $0.name == "Phoenix" }?.url)

        viewModel.setSelection([folder])

        XCTAssertFalse(viewModel.canChoose)
    }
}
