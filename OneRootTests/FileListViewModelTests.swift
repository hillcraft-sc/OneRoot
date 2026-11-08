import XCTest
import Observation
@testable import OneRoot

@MainActor
final class FileListViewModelTests: XCTestCase {
    private var root: URL!
    private var child: URL!
    private var grandchild: URL!
    private var viewModel: FileListViewModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        child = root.appendingPathComponent("child", isDirectory: true)
        grandchild = child.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandchild, withIntermediateDirectories: true)
        // Isolated TrashOriginService / NavigationHistoryStore — both
        // default to backing onto UserDefaults.standard, and
        // restore/moveToTrash and navigation tests would otherwise pollute
        // real app state across test runs.
        viewModel = FileListViewModel(
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Loading and listing states

    func testLoadingIsSetDuringNavigationAndClearedAfter() async {
        let task = viewModel.navigate(to: root)
        XCTAssertTrue(viewModel.isLoading)

        await task.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.listingErrorMessage)
    }

    func testAPassiveRefreshDoesNotShowLoading() async {
        await viewModel.navigate(to: root).value

        let task = viewModel.refresh()

        XCTAssertFalse(viewModel.isLoading)
        await task?.value
    }

    func testUnreadableFolderReportsPermissionDenied() async throws {
        try XCTSkipIf(getuid() == 0, "root can read anything")
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        await viewModel.navigate(to: locked).value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isPermissionDenied)
        XCTAssertNotNil(viewModel.listingErrorMessage)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testNavigatingAwayClearsTheListingError() async throws {
        try XCTSkipIf(getuid() == 0, "root can read anything")
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        await viewModel.navigate(to: locked).value

        await viewModel.navigate(to: child).value

        XCTAssertFalse(viewModel.isPermissionDenied)
        XCTAssertNil(viewModel.listingErrorMessage)
    }

    func testNavigatingElsewhereClearsTheSelection() async {
        await viewModel.navigate(to: root).value
        viewModel.updateSelection(viewModel.items)
        XCTAssertFalse(viewModel.selectedNodes.isEmpty)

        await viewModel.navigate(to: child).value

        XCTAssertTrue(viewModel.selectedNodes.isEmpty)
    }

    func testClearSelectionEmptiesItAtOnceAndAsksTheViewToo() async {
        await viewModel.navigate(to: root).value
        viewModel.updateSelection(viewModel.items)
        let trigger = viewModel.clearSelectionTrigger

        viewModel.clearSelection()

        XCTAssertTrue(viewModel.selectedNodes.isEmpty)
        XCTAssertEqual(viewModel.clearSelectionTrigger, trigger + 1)
    }

    #if !SWIFT_PACKAGE // FileTableController is the Mac app's AppKit list
    func testSameListingComparesNodesByIdentity() {
        let a = FileNode(url: root, name: "a", isDirectory: true, size: nil, modificationDate: nil, kind: nil)
        let b = FileNode(url: child, name: "b", isDirectory: true, size: nil, modificationDate: nil, kind: nil)
        let aAgain = FileNode(url: root, name: "a", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        XCTAssertTrue(FileTableController.isSameListing([a, b], [a, b]))
        XCTAssertFalse(FileTableController.isSameListing([a, b], [b, a]), "a re-sort is a new listing")
        XCTAssertFalse(FileTableController.isSameListing([a], [aAgain]), "a fresh read is a new listing")
        XCTAssertFalse(FileTableController.isSameListing([a], [a, b]))
    }
    #endif

    func testNavigateUpdatesCurrentDirectory() async {
        await viewModel.navigate(to: root).value

        XCTAssertEqual(viewModel.currentDirectory, root)
    }

    func testBackAndForwardTraverseHistory() async {
        await viewModel.navigate(to: root).value
        await viewModel.navigate(to: child).value
        await viewModel.navigate(to: grandchild).value

        XCTAssertTrue(viewModel.canGoBack)
        XCTAssertFalse(viewModel.canGoForward)

        await viewModel.goBack()?.value
        XCTAssertEqual(viewModel.currentDirectory, child)
        XCTAssertTrue(viewModel.canGoForward)

        await viewModel.goBack()?.value
        XCTAssertEqual(viewModel.currentDirectory, root)
        XCTAssertFalse(viewModel.canGoBack)

        await viewModel.goForward()?.value
        XCTAssertEqual(viewModel.currentDirectory, child)
    }

    func testGoingBackSeveralStepsKeepsTheFoldersPassedAsForwardHistory() async {
        await viewModel.navigate(to: root).value
        await viewModel.navigate(to: child).value
        await viewModel.navigate(to: grandchild).value

        await viewModel.goBack(steps: 2)?.value
        XCTAssertEqual(viewModel.currentDirectory, root)
        XCTAssertFalse(viewModel.canGoBack)
        XCTAssertEqual(viewModel.forwardHistory, [child, grandchild])

        await viewModel.goForward(steps: 2)?.value
        XCTAssertEqual(viewModel.currentDirectory, grandchild)
        XCTAssertEqual(viewModel.backHistory, [child, root])
        XCTAssertNil(viewModel.goBack(steps: 3))
    }

    func testNewNavigationClearsForwardStack() async {
        await viewModel.navigate(to: root).value
        await viewModel.navigate(to: child).value
        await viewModel.goBack()?.value
        XCTAssertTrue(viewModel.canGoForward)

        await viewModel.navigate(to: grandchild).value
        XCTAssertFalse(viewModel.canGoForward)
    }

    func testGoUpNavigatesToParent() async {
        await viewModel.navigate(to: grandchild).value
        await viewModel.goUp()?.value

        XCTAssertEqual(viewModel.currentDirectory, child)
    }

    /// The current directory is deleted out from under an open tab (from
    /// the tree, say): the tab goes to the nearest folder above that still
    /// exists, not home — so a Workspace or split pane stays where it was.
    func testRefreshOnDeletedDirectoryGoesToNearestExistingParent() async throws {
        await viewModel.navigate(to: grandchild).value
        try FileManager.default.removeItem(at: child)

        await viewModel.refresh()?.value

        XCTAssertEqual(viewModel.currentDirectory?.standardizedFileURL, root.standardizedFileURL)
    }

    func testNearestExistingFolderStopsShortOfVolumes() async {
        let service = FileSystemService()

        let gone = await service.nearestExistingFolder(above: URL(fileURLWithPath: "/Volumes/OneRootTestsGone/Shows"))

        XCTAssertNil(gone, "an ejected drive or dropped share falls back to home")
    }

    func testGoUpAtFilesystemRootIsNoOp() async {
        let filesystemRoot = URL(fileURLWithPath: "/")
        await viewModel.navigate(to: filesystemRoot).value

        XCTAssertFalse(viewModel.canGoUp)
        XCTAssertNil(viewModel.goUp())
    }

    func testCreateFolderAddsItToTheCurrentDirectoryListing() async {
        await viewModel.navigate(to: root).value
        viewModel.promptForNewFolder()

        await viewModel.createFolder(named: "Docs")?.value

        XCTAssertTrue(viewModel.items.contains { $0.name == "Docs" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Docs").path))
    }

    func testCreateFolderWithoutPendingIntentIsANoOp() async {
        await viewModel.navigate(to: root).value

        await viewModel.createFolder(named: "Docs")?.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Docs").path))
    }

    func testCreateFolderAndOpenNavigatesIntoTheNewFolder() async {
        await viewModel.navigate(to: root).value
        viewModel.promptForNewFolderAndOpen()

        await viewModel.createFolder(named: "Docs")?.value

        // `.path`, not raw `URL` equality — `appendingPathComponent`
        // infers the directory flag (and therefore a trailing slash) by
        // checking whether the path exists on disk *at construction time*,
        // so the same path constructed before vs. after creation compares
        // unequal as `URL` despite being the same location.
        XCTAssertEqual(viewModel.currentDirectory?.path, root.appendingPathComponent("Docs").path)
    }

    func testCreateFolderHereCreatesInsideTheGivenNodeAndNavigatesIntoIt() async throws {
        await viewModel.navigate(to: root).value
        let targetNode = try XCTUnwrap(viewModel.items.first { $0.name == "child" })
        viewModel.promptForNewFolderHere(in: targetNode)

        await viewModel.createFolder(named: "Docs")?.value

        // `.resolvingSymlinksInPath()` — `targetNode.url` came from
        // `FileManager.contentsOfDirectory`, which returns paths resolved
        // through symlinks (e.g. `/private/var/...`), while `child` here
        // is built by hand via `appendingPathComponent` and stays
        // unresolved (`/var/...`).
        XCTAssertEqual(viewModel.currentDirectory?.resolvingSymlinksInPath().path, child.appendingPathComponent("Docs").resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.appendingPathComponent("Docs").path))
    }

    func testRenameUpdatesTheCurrentDirectoryListing() async throws {
        let fileURL = root.appendingPathComponent("old.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value
        let node = try XCTUnwrap(viewModel.items.first { $0.name == "old.txt" })

        await viewModel.rename(node, to: "new.txt").value

        XCTAssertTrue(viewModel.items.contains { $0.name == "new.txt" })
        XCTAssertFalse(viewModel.items.contains { $0.name == "old.txt" })
    }

    func testMoveToTrashRemovesItemFromTheCurrentDirectoryListing() async throws {
        isolateTrashOnLinux()
        let fileURL = root.appendingPathComponent("throwaway.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value
        let node = try XCTUnwrap(viewModel.items.first { $0.name == "throwaway.txt" })

        await viewModel.moveToTrash([node]).value

        XCTAssertFalse(viewModel.items.contains { $0.name == "throwaway.txt" })
    }

    func testSearchTextFiltersItemsByNameCaseInsensitively() async throws {
        try "x".write(to: root.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value

        viewModel.searchText = "report"

        XCTAssertEqual(viewModel.items.map(\.name), ["Report.txt"])
    }

    func testClearingSearchTextRestoresFullListing() async throws {
        try "x".write(to: root.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value
        viewModel.searchText = "report"

        viewModel.searchText = ""

        XCTAssertEqual(Set(viewModel.items.map(\.name)), Set(["Report.txt", "notes.md", "child"]))
    }

    func testTheFilterStaysOnInTheNextFolder() async throws {
        try "x".write(to: child.appendingPathComponent("Report 2.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: child.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value
        viewModel.searchText = "report"

        await viewModel.navigate(to: child).value

        XCTAssertEqual(viewModel.searchText, "report")
        XCTAssertEqual(viewModel.items.map(\.name), ["Report 2.txt"])
        viewModel.clearFilter()
        XCTAssertTrue(Set(viewModel.items.map(\.name)).isSuperset(of: ["Report 2.txt", "notes.md"]))
    }

    func testTaggingSeveralItemsKeepsTheirOtherTags() async throws {
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
        try "x".write(to: a, atomically: true, encoding: .utf8)
        try "x".write(to: b, atomically: true, encoding: .utf8)
        try TagService().setTags(["Blue"], on: a)
        await viewModel.navigate(to: root).value
        let nodes = viewModel.items.filter { $0.name.hasSuffix(".txt") }

        let error = await viewModel.setTag("Red", adding: true, on: nodes)

        XCTAssertNil(error)
        XCTAssertEqual(try TagService().tags(of: a), ["Blue", "Red"])
        XCTAssertEqual(try TagService().tags(of: b), ["Red"])

        // The selection (what the Inspector shows) picks up the new tags.
        viewModel.updateSelection(nodes)
        let refreshed = viewModel.items.filter { $0.name.hasSuffix(".txt") }
        await viewModel.setTag("red", adding: false, on: refreshed)
        XCTAssertEqual(viewModel.selectedNodes.map(\.tags), [["Blue"], []])
        XCTAssertEqual(try TagService().tags(of: a), ["Blue"])
        XCTAssertEqual(try TagService().tags(of: b), [])
    }

    func testFilterChipsNarrowTheList() async throws {
        try "x".write(to: root.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value

        viewModel.filter.kinds = [.images]
        XCTAssertEqual(viewModel.items.map(\.name), ["photo.jpg"]) // the "child" folder has no kind

        viewModel.filter.kinds = []
        viewModel.filter.itemType = .foldersOnly
        XCTAssertEqual(viewModel.items.map(\.name), ["child"])
    }

    func testSearchTextAndFilterPatternStayInStep() async throws {
        await viewModel.navigate(to: root).value
        viewModel.searchText = "rep"
        XCTAssertEqual(viewModel.filter.pattern, "rep")
        viewModel.filter = SearchChipBuilder.removing(.name, from: viewModel.filter)
        XCTAssertEqual(viewModel.searchText, "")
    }

    func testAnUnfinishedRegexListsNothingAndSaysWhy() async throws {
        try "x".write(to: root.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        await viewModel.navigate(to: root).value
        viewModel.filter.patternMode = .regex
        viewModel.searchText = "Rep("
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNotNil(viewModel.filterError)
        viewModel.searchText = "^Rep"
        XCTAssertEqual(viewModel.items.map(\.name), ["Report.txt"])
        XCTAssertNil(viewModel.filterError)
    }

    func testSubfolderSearchCarriesTheFilterRootedHere() async throws {
        await viewModel.navigate(to: root).value
        viewModel.searchText = "rep"
        viewModel.filter.kinds = [.documents]
        let criteria = try XCTUnwrap(viewModel.filterAsSubfolderSearch())
        XCTAssertEqual(criteria.root, root)
        XCTAssertEqual(criteria.pattern, "rep")
        XCTAssertEqual(criteria.kinds, [.documents])
        XCTAssertEqual(criteria.mode, .nameAndMetadata)
    }

    func testHandleDropMovesFileIntoTargetDirectory() async throws {
        let fileURL = root.appendingPathComponent("dragged.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.handleDrop(urls: [fileURL], into: child, move: true)?.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.appendingPathComponent("dragged.txt").path))
    }

    func testHandleDropCopiesFileIntoTargetDirectory() async throws {
        let fileURL = root.appendingPathComponent("dragged.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.handleDrop(urls: [fileURL], into: child, move: false)?.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "copy should leave the original in place")
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.appendingPathComponent("dragged.txt").path))
    }

    func testHandleDropMoveOntoTheSameFolderIsANoOp() async throws {
        let fileURL = root.appendingPathComponent("already-here.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.handleDrop(urls: [fileURL], into: root, move: true)?.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "child" }, ["already-here.txt"])
    }

    func testHandleDropRefreshesListingWhenTargetIsCurrentDirectory() async throws {
        let fileURL = root.appendingPathComponent("dragged.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        await viewModel.navigate(to: child).value

        await viewModel.handleDrop(urls: [fileURL], into: child, move: true)?.value

        XCTAssertTrue(viewModel.items.contains { $0.name == "dragged.txt" })
    }
}

@MainActor
final class FileListViewModelViewModeTests: XCTestCase {
    func testViewModeFollowsEachFoldersRememberedChoice() async throws {
        let suiteName = "FileListViewModelViewModeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = FileListViewModel(folderViewModes: FolderViewModeService(defaults: defaults))

        await viewModel.navigate(to: photos).value
        XCTAssertEqual(viewModel.viewMode, .list)
        viewModel.setViewMode(.icons)

        await viewModel.navigate(to: documents).value
        XCTAssertEqual(viewModel.viewMode, .list, "a different folder keeps its own mode")

        await viewModel.navigate(to: photos).value
        XCTAssertEqual(viewModel.viewMode, .icons, "coming back restores the remembered mode")
    }

    func testSettingTheSameViewModePublishesNothing() throws {
        let suiteName = "FileListViewModelViewModeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = FileListViewModel(folderViewModes: FolderViewModeService(defaults: defaults))
        var notified = false
        withObservationTracking { _ = viewModel.viewMode } onChange: { notified = true }

        viewModel.setViewMode(.list)

        XCTAssertFalse(notified)
    }
}

#if os(macOS) // the Mac clipboard (NSPasteboard)
@MainActor
final class ClipboardTrackerTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    func testNothingPendingUntilOneRootWrites() {
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL]) // something another app copied

        XCTAssertNil(ClipboardTracker(clipboard: PasteboardClipboard(pasteboard)).pending)
    }

    func testRecordedCopyIsPendingUntilTheClipboardChanges() {
        let tracker = ClipboardTracker(clipboard: PasteboardClipboard(pasteboard))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/a") as NSURL, URL(fileURLWithPath: "/b") as NSURL])
        tracker.record(count: 2, operation: .copy)

        tracker.refresh()
        XCTAssertEqual(tracker.pending, .init(count: 2, operation: .copy))

        pasteboard.clearContents() // e.g. another app copied, or a cut was pasted
        tracker.refresh()
        XCTAssertNil(tracker.pending)
    }
}
#endif

@MainActor
final class FolderSizePreferenceStoreTests: XCTestCase {
    func testSettingPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        FolderSizePreferenceStore(defaults: defaults).set(true)

        XCTAssertTrue(FolderSizePreferenceStore(defaults: defaults).calculateAll)
    }
}


/// Copy, Cut and Paste through an injected clipboard — never the real one.
@MainActor
final class FileListClipboardTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("from"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("to"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("from/a.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeViewModel(_ clipboard: FileClipboard) -> FileListViewModel {
        FileListViewModel(
            trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)),
            undoCenter: FileUndoCenter(trashOriginService: TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!), presentError: { _ in }),
            clipboard: clipboard
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testCopyThenPasteCopies() async throws {
        let clipboard = MemoryClipboard()
        let viewModel = makeViewModel(clipboard)
        await viewModel.navigate(to: root.appendingPathComponent("from")).value
        viewModel.copySelection(viewModel.items)
        XCTAssertTrue(viewModel.canPaste)

        await viewModel.navigate(to: root.appendingPathComponent("to")).value
        viewModel.paste()
        let copy = root.appendingPathComponent("to/a.txt")
        await waitUntil { FileManager.default.fileExists(atPath: copy.path) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("from/a.txt").path))
        XCTAssertTrue(clipboard.hasFiles, "a copy can be pasted again")
    }

    func testCutThenPasteMovesAndEmptiesTheClipboard() async throws {
        let clipboard = MemoryClipboard()
        let viewModel = makeViewModel(clipboard)
        await viewModel.navigate(to: root.appendingPathComponent("from")).value
        viewModel.cutSelection(viewModel.items)

        await viewModel.navigate(to: root.appendingPathComponent("to")).value
        viewModel.paste()
        await waitUntil { !clipboard.hasFiles }

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("to/a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("from/a.txt").path))
        XCTAssertFalse(clipboard.hasFiles, "a cut is used up by pasting it")
    }

    func testCopyPathPutsTextNotFiles() async {
        let clipboard = MemoryClipboard()
        let viewModel = makeViewModel(clipboard)
        let file = root.appendingPathComponent("from/a.txt")

        viewModel.copyPaths([file])

        XCTAssertEqual(clipboard.string, file.path)
        XCTAssertFalse(viewModel.canPaste)
    }
}
