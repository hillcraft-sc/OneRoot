import XCTest
import Observation
@testable import OneRoot

/// Lets a test fire a change notification on demand instead of depending on
/// real FSEvents — a *real* `FileWatcher` in a test races against genuine
/// background filesystem activity on whatever machine runs it. The real
/// FSEvents plumbing itself is covered by `FileWatcherTests`; this is only
/// for testing `FolderHierarchyViewModel`'s own translation of a changed
/// path into a refresh request, and which roots it watches.
private final class FakeFileWatcher: FileWatching {
    private var changedPaths: Set<String> = []
    private(set) var watchedURLs: [URL] = []

    var onChange: (@MainActor () -> Void)?
    func watch(_ urls: [URL]) { watchedURLs = urls }
    func stop() {}
    func drainChangedPaths() -> Set<String> {
        defer { changedPaths.removeAll() }
        return changedPaths
    }

    func fireChange(paths: Set<String>) {
        changedPaths = paths
        MainActor.assumeIsolated { onChange?() }
    }
}

@MainActor
final class FolderHierarchyViewModelTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeIsolatedTrashOriginService() -> TrashOriginService {
        TrashOriginService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func makeViewModel(
        pins: PinnedLocationsStore? = nil,
        fileWatcher: FileWatching = NullFileWatcher()
    ) -> FolderHierarchyViewModel {
        FolderHierarchyViewModel(
            pinnedLocations: pins ?? makeIsolatedPinnedLocationsStore(),
            trashOriginService: makeIsolatedTrashOriginService(),
            fileWatcher: fileWatcher,
            undoCenter: FileUndoCenter(presentError: { _ in })
        )
    }

    private func root(_ url: URL, _ name: String = "root", kind: DestinationKind = .folder) -> HierarchyRoot {
        HierarchyRoot(url: url, name: name, kind: kind)
    }

    // MARK: Empty Trash

    private func trashNode(_ url: URL) -> FileNode {
        FileNode(url: url, name: "Trash", isDirectory: true, size: nil, modificationDate: nil, kind: nil)
    }

    func testEmptyTrashRemovesEverythingIncludingHiddenItems() async throws {
        let trash = tempDirectory.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try "a".write(to: trash.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "h".write(to: trash.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        let viewModel = makeViewModel()
        await viewModel.emptyTrash(trashNode(trash)).value
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
    }

    func testEmptyTrashWithNoTrashFolderIsNotAnError() async {
        let missing = tempDirectory.appendingPathComponent("never-created", isDirectory: true)
        let viewModel = makeViewModel()
        await viewModel.emptyTrash(trashNode(missing)).value
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMissingErrorsAreRecognized() {
        XCTAssertTrue(FileSystemError.isMissing(CocoaError(.fileReadNoSuchFile)))
        XCTAssertTrue(FileSystemError.isMissing(FileSystemError.cannotList(tempDirectory, underlying: CocoaError(.fileNoSuchFile))))
        XCTAssertFalse(FileSystemError.isMissing(CocoaError(.fileWriteNoPermission)))
    }

    // MARK: Roots

    func testSetRootsShowsOneNodePerRootTaggedWithItsKind() {
        let viewModel = makeViewModel()

        viewModel.setRoots([root(tempDirectory, "Temp", kind: .pinned)])

        XCTAssertEqual(viewModel.roots.map(\.url), [tempDirectory])
        XCTAssertEqual(viewModel.roots.first?.name, "Temp")
        XCTAssertEqual(viewModel.roots.first?.kind, "Pinned")
    }

    func testSetRootsWithTheSameRootsDoesNotRepublish() {
        let viewModel = makeViewModel()
        viewModel.setRoots([root(tempDirectory)])
        var notified = false
        withObservationTracking { _ = viewModel.roots } onChange: { notified = true }

        viewModel.setRoots([root(tempDirectory)])

        XCTAssertFalse(notified)
    }

    func testReturningToARootReusesItsNodeAndLoadedChildren() {
        let viewModel = makeViewModel()
        let other = tempDirectory.appendingPathComponent("other")
        viewModel.setRoots([root(tempDirectory)])
        let first = try! XCTUnwrap(viewModel.roots.first)
        first.children = [] // as if already expanded and loaded

        viewModel.setRoots([root(other)])
        viewModel.setRoots([root(tempDirectory)])

        XCTAssertTrue(viewModel.roots.first === first, "expected the same FileNode instance to be reused")
        XCTAssertEqual(viewModel.roots.first?.children?.count, 0)
    }

    func testReturningToALoadedRootRefreshesWhatWasLoaded() {
        // It wasn't watched while away, so anything already loaded might be stale.
        let viewModel = makeViewModel()
        let other = tempDirectory.appendingPathComponent("other")
        viewModel.setRoots([root(tempDirectory)])
        viewModel.roots.first?.children = []
        viewModel.setRoots([root(other)])
        viewModel.refreshRequests = []

        viewModel.setRoots([root(tempDirectory)])

        XCTAssertTrue(viewModel.refreshRequests.contains(tempDirectory))
    }

    func testRenamedRootGetsANewNodeButKeepsItsChildren() {
        let viewModel = makeViewModel()
        viewModel.setRoots([root(tempDirectory, "Old")])
        let first = try! XCTUnwrap(viewModel.roots.first)
        first.children = []

        viewModel.setRoots([root(tempDirectory, "New")])

        XCTAssertEqual(viewModel.roots.first?.name, "New")
        XCTAssertEqual(viewModel.roots.first?.children?.count, 0)
    }

    func testWatchesOnlyTheCurrentRoots() {
        let watcher = FakeFileWatcher()
        let viewModel = makeViewModel(fileWatcher: watcher)
        let other = tempDirectory.appendingPathComponent("other")

        viewModel.setRoots([root(tempDirectory)])
        viewModel.setRoots([root(other)])

        XCTAssertEqual(watcher.watchedURLs, [other])
    }

    func testEjectForwardsTheRootToTheEjectHandler() {
        let viewModel = makeViewModel()
        var ejected: [URL] = []
        viewModel.ejectHandler = { ejected.append($0) }
        let node = FileNode(url: tempDirectory, name: "USB", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        viewModel.eject(node)

        XCTAssertEqual(ejected, [tempDirectory])
    }

    func testTogglePinGoesThroughTheSharedStore() {
        let pins = makeIsolatedPinnedLocationsStore()
        let viewModel = makeViewModel(pins: pins)
        let node = FileNode(url: tempDirectory, name: "Temp", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        viewModel.togglePin(node)

        XCTAssertTrue(pins.isPinned(tempDirectory))
        XCTAssertTrue(viewModel.isPinned(tempDirectory))
    }

    // MARK: Tree operations

    func testChildrenOfExcludesFiles() async throws {
        try "x".write(to: tempDirectory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("subfolder"), withIntermediateDirectories: true)
        let viewModel = makeViewModel()
        let node = FileNode(url: tempDirectory, name: "root", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        let children = await viewModel.children(of: node)

        XCTAssertEqual(children.map(\.name), ["subfolder"])
    }

    func testMoveToTrashUnpins() async throws {
        isolateTrashOnLinux()
        let folder = tempDirectory.appendingPathComponent("pinned")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let viewModel = makeViewModel()
        let node = FileNode(url: folder, name: "pinned", isDirectory: true, size: nil, modificationDate: nil, kind: nil)
        viewModel.togglePin(node)
        XCTAssertTrue(viewModel.isPinned(folder))

        await viewModel.moveToTrash(node).value

        XCTAssertFalse(viewModel.isPinned(folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testHandleDropMovesFileIntoTargetNode() async throws {
        let destination = tempDirectory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("dragged.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let viewModel = makeViewModel()
        let node = FileNode(url: destination, name: "destination", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        await viewModel.handleDrop(urls: [fileURL], into: node, move: true).value

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("dragged.txt").path))
    }

    func testHandleDropCopyIntoTargetNodeLeavesOriginalInPlace() async throws {
        let destination = tempDirectory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("dragged.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let viewModel = makeViewModel()
        let node = FileNode(url: destination, name: "destination", isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        await viewModel.handleDrop(urls: [fileURL], into: node, move: false).value

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("dragged.txt").path))
    }

    func testHandleDropMoveOntoTheSameFolderIsANoOp() async throws {
        let fileURL = tempDirectory.appendingPathComponent("already-here.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let viewModel = makeViewModel()
        let node = FileNode(url: tempDirectory, name: tempDirectory.lastPathComponent, isDirectory: true, size: nil, modificationDate: nil, kind: nil)

        await viewModel.handleDrop(urls: [fileURL], into: node, move: true).value

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testExternalChangeRequestsARefreshOfTheChangedItemsParent() {
        let watchedRoot = tempDirectory.appendingPathComponent("watched")
        let fakeWatcher = FakeFileWatcher()
        let viewModel = makeViewModel(fileWatcher: fakeWatcher)
        viewModel.setRoots([root(watchedRoot)])

        fakeWatcher.fireChange(paths: [watchedRoot.appendingPathComponent("new.txt").path])

        // `.path` rather than raw `URL` equality — `deletingLastPathComponent()`
        // marks its result as a directory, which renders with a trailing
        // slash and compares unequal to a plain `appendingPathComponent`
        // URL for the same path.
        XCTAssertTrue(viewModel.refreshRequests.contains { $0.path == watchedRoot.path })
    }

    func testExternalChangeBatchesMultiplePathsIntoOneUpdate() {
        // A single filesystem change can be reported as more than one path
        // at once (e.g. a new file plus its parent directory's own mtime
        // bump) — both should land in `refreshRequests` from one signal.
        let watchedRoot = tempDirectory.appendingPathComponent("watched")
        let otherRoot = tempDirectory.appendingPathComponent("other")
        let fakeWatcher = FakeFileWatcher()
        let viewModel = makeViewModel(fileWatcher: fakeWatcher)
        viewModel.setRoots([root(watchedRoot), root(otherRoot, "other")])

        fakeWatcher.fireChange(paths: [
            watchedRoot.appendingPathComponent("new.txt").path,
            otherRoot.appendingPathComponent("also-new.txt").path,
        ])

        XCTAssertEqual(Set(viewModel.refreshRequests.map(\.path)), [watchedRoot.path, otherRoot.path])
    }
}
