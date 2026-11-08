import XCTest
@testable import OneRoot

@MainActor
final class HierarchyCoordinatorTests: XCTestCase {
    private var home: URL!
    private var pinnedFolder: URL!
    private var outside: URL!
    private var windowViewModel: WindowViewModel!
    private var destinations: DestinationsViewModel!
    private var hierarchy: FolderHierarchyViewModel!
    private var coordinator: HierarchyCoordinator!
    private var workspaces: WorkspaceStore!

    override func setUp() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = base.appendingPathComponent("home", isDirectory: true)
        pinnedFolder = home.appendingPathComponent("Projects", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        for url in [pinnedFolder, outside] {
            try FileManager.default.createDirectory(at: url!, withIntermediateDirectories: true)
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    /// The temp folder's own volume stands in for the boot volume, so every
    /// location here has a destination containing it.
    private func makeCoordinator(pins: [URL] = [], loadVolumes: Bool = true) {
        let pinStore = makeIsolatedPinnedLocationsStore()
        pins.forEach(pinStore.toggle)
        windowViewModel = WindowViewModel(
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)),
            opensDefaultTab: false
        )
        windowViewModel.openNewTab(at: home)
        destinations = DestinationsViewModel(volumeService: NullVolumeProvider(), pinnedLocations: pinStore, homeURL: home)
        if loadVolumes {
            destinations.applyVolumes([makeTestVolume(name: "Disk", path: "/")])
        }
        hierarchy = FolderHierarchyViewModel(pinnedLocations: pinStore)
        workspaces = WorkspaceStore(service: WorkspaceService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        coordinator = HierarchyCoordinator(windowViewModel: windowViewModel, destinations: destinations, hierarchy: hierarchy, workspaces: workspaces)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private var activeTab: Tab { windowViewModel.activeTab! }

    func testTheActiveTabIsRootedAtItsDestination() async {
        makeCoordinator()

        await waitUntil { self.hierarchy.roots.first?.url == self.home }

        XCTAssertEqual(activeTab.hierarchyRoot?.kind, .home)
        XCTAssertEqual(hierarchy.roots.map(\.url), [home])
    }

    func testLeavingTheRootReRootsTheTab() async {
        makeCoordinator()
        await waitUntil { self.activeTab.hierarchyRoot?.kind == .home }

        await activeTab.fileListViewModel.navigate(to: outside).value

        await waitUntil { self.activeTab.hierarchyRoot?.kind == .bootVolume }
        XCTAssertEqual(activeTab.hierarchyRoot?.url.path, "/")
        XCTAssertEqual(hierarchy.roots.first?.url.path, "/")
    }

    func testBrowsingInsideTheRootKeepsIt() async {
        makeCoordinator(pins: [pinnedFolder])
        await waitUntil { self.activeTab.hierarchyRoot?.kind == .home }

        await activeTab.fileListViewModel.navigate(to: pinnedFolder).value
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(activeTab.hierarchyRoot?.kind, .home, "a pinned folder inside Home shouldn't steal the root")
    }

    func testEachTabKeepsItsOwnRoot() async throws {
        makeCoordinator(pins: [pinnedFolder])
        await waitUntil { self.activeTab.hierarchyRoot?.kind == .home }
        let first = activeTab
        let pinned = try XCTUnwrap(destinations.allDestinations.first { $0.kind == .pinned })

        windowViewModel.selectDestination(pinned, inNewTab: true)
        await waitUntil { self.hierarchy.roots.first?.url == self.pinnedFolder }
        windowViewModel.selectTab(first)
        await waitUntil { self.hierarchy.roots.first?.url == self.home }

        XCTAssertEqual(first.hierarchyRoot?.kind, .home)
        XCTAssertEqual(windowViewModel.tabs[1].hierarchyRoot?.kind, .pinned)
        XCTAssertEqual(hierarchy.roots.first?.url, home)
    }

    func testUnpinningTheRootReRootsTheTab() async throws {
        makeCoordinator(pins: [pinnedFolder])
        let pinned = try XCTUnwrap(destinations.allDestinations.first { $0.kind == .pinned })
        windowViewModel.selectDestination(pinned)
        await waitUntil { self.activeTab.hierarchyRoot?.kind == .pinned }

        destinations.unpin(pinned)

        await waitUntil { self.activeTab.hierarchyRoot?.kind == .home }
        XCTAssertEqual(activeTab.hierarchyRoot?.url, home)
    }

    func testRootIsNotStoredUntilVolumesHaveLoaded() async {
        makeCoordinator(loadVolumes: false)
        await waitUntil { !self.hierarchy.roots.isEmpty }

        // Shown provisionally, but not saved on the tab as a guess.
        XCTAssertEqual(hierarchy.roots.first?.url, home)
        XCTAssertNil(activeTab.hierarchyRoot)

        destinations.applyVolumes([makeTestVolume(name: "Disk", path: "/")])
        await waitUntil { self.activeTab.hierarchyRoot != nil }
        XCTAssertEqual(activeTab.hierarchyRoot?.kind, .home)
    }

    func testEjectableRootsReachTheHierarchy() async {
        makeCoordinator()
        let usb = makeTestVolume(name: "USB", path: "/Volumes/USB", isEjectable: true)

        destinations.applyVolumes([makeTestVolume(name: "Disk", path: "/"), usb])

        await waitUntil { self.hierarchy.ejectableRootURLs.contains(usb.url) }
        XCTAssertEqual(hierarchy.ejectableRootURLs, [usb.url])
    }

    // MARK: Workspaces

    private func makeWorkspace() -> Workspace {
        let workspace = Workspace(name: "Phoenix", folders: [pinnedFolder, outside])
        workspaces.save(workspace)
        return workspace
    }

    func testOpeningAWorkspaceShowsAllItsFoldersAsRoots() async {
        makeCoordinator()
        let workspace = makeWorkspace()

        windowViewModel.openWorkspace(workspace)

        await waitUntil { self.hierarchy.roots.count == 2 }
        XCTAssertEqual(hierarchy.roots.map(\.url), [pinnedFolder, outside])
        XCTAssertEqual(activeTab.workspaceID, workspace.id)
        await waitUntil { self.activeTab.fileListViewModel.currentDirectory == self.pinnedFolder }
        XCTAssertEqual(activeTab.fileListViewModel.currentDirectory, pinnedFolder)
    }

    func testMovingBetweenTheWorkspacesFoldersKeepsIt() async {
        makeCoordinator()
        let workspace = makeWorkspace()
        windowViewModel.openWorkspace(workspace)
        await waitUntil { self.hierarchy.roots.count == 2 }

        await activeTab.fileListViewModel.navigate(to: outside).value
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(activeTab.workspaceID, workspace.id)
        XCTAssertEqual(hierarchy.roots.map(\.url), [pinnedFolder, outside])
    }

    func testLeavingTheWorkspacesFoldersEndsIt() async {
        makeCoordinator()
        windowViewModel.openWorkspace(makeWorkspace())
        await waitUntil { self.hierarchy.roots.count == 2 }

        await activeTab.fileListViewModel.navigate(to: home).value

        await waitUntil { self.activeTab.workspaceID == nil }
        XCTAssertNil(activeTab.workspaceID)
        await waitUntil { self.hierarchy.roots.map(\.url) == [self.home] }
        XCTAssertEqual(hierarchy.roots.map(\.url), [home])
    }

    func testDeletingTheWorkspaceEndsIt() async {
        makeCoordinator()
        let workspace = makeWorkspace()
        windowViewModel.openWorkspace(workspace)
        await waitUntil { self.hierarchy.roots.count == 2 }

        workspaces.delete(workspace.id)

        await waitUntil { self.activeTab.workspaceID == nil }
        XCTAssertNil(activeTab.workspaceID)
        await waitUntil { self.hierarchy.roots.count == 1 }
        XCTAssertEqual(hierarchy.roots.count, 1)
    }

    func testChoosingADestinationLeavesTheWorkspace() async {
        makeCoordinator()
        windowViewModel.openWorkspace(makeWorkspace())
        await waitUntil { self.hierarchy.roots.count == 2 }

        windowViewModel.selectDestination(Destination(url: home, name: "home", kind: .home))

        XCTAssertNil(activeTab.workspaceID)
        await waitUntil { self.hierarchy.roots.map(\.url) == [self.home] }
        XCTAssertEqual(hierarchy.roots.map(\.url), [home])
    }
}
