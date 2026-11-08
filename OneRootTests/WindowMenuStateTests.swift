import Combine
import XCTest
@testable import OneRoot

@MainActor
final class WindowMenuStateTests: XCTestCase {
    private var tempRoot: URL!
    private var tempChild: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        tempChild = tempRoot.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: tempChild, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeHistoryStore() -> NavigationHistoryStore {
        NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    private var destinations: DestinationsViewModel!
    private var hierarchy: FolderHierarchyViewModel!

    private func makeConfigured(history: NavigationHistoryStore) -> (WindowMenuState, WindowViewModel) {
        let windowViewModel = WindowViewModel(navigationHistory: history)
        destinations = DestinationsViewModel(volumeService: NullVolumeProvider(), pinnedLocations: makeIsolatedPinnedLocationsStore())
        hierarchy = FolderHierarchyViewModel(pinnedLocations: makeIsolatedPinnedLocationsStore())
        let menuState = WindowMenuState(history: history)
        menuState.configure(windowViewModel: windowViewModel, destinationsViewModel: destinations, hierarchyViewModel: hierarchy)
        return (menuState, windowViewModel)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testConfigureExposesActiveTabAndInitialMirrors() {
        let (menuState, windowViewModel) = makeConfigured(history: makeHistoryStore())

        XCTAssertTrue(menuState.fileListViewModel === windowViewModel.activeTab?.fileListViewModel)
        XCTAssertFalse(menuState.canGoBack)
        XCTAssertFalse(menuState.canGoForward)
        XCTAssertEqual(menuState.selectionCount, 0)
    }

    func testConfigureIsIdempotent() {
        let (menuState, windowViewModel) = makeConfigured(history: makeHistoryStore())

        menuState.configure(windowViewModel: windowViewModel, destinationsViewModel: destinations, hierarchyViewModel: hierarchy)

        XCTAssertTrue(menuState.fileListViewModel === windowViewModel.activeTab?.fileListViewModel)
    }

    func testTriggerCountersIncrement() {
        let menuState = WindowMenuState(history: makeHistoryStore())

        XCTAssertEqual(menuState.connectToServerRequestCount, 0)
        menuState.requestConnectToServer()
        menuState.requestConnectToServer()
        XCTAssertEqual(menuState.connectToServerRequestCount, 2)

        XCTAssertEqual(menuState.shortcutsQuickViewRequestCount, 0)
        menuState.requestShortcutsQuickView()
        XCTAssertEqual(menuState.shortcutsQuickViewRequestCount, 1)
    }

    func testRecentLocationsSeededFromStore() {
        let store = makeHistoryStore()
        store.record(URL(fileURLWithPath: "/a"))
        store.record(URL(fileURLWithPath: "/b"))

        let menuState = WindowMenuState(history: store)

        XCTAssertEqual(menuState.recentLocations, [URL(fileURLWithPath: "/b"), URL(fileURLWithPath: "/a")])
    }

    func testRecentLocationsFollowStoreChanges() async {
        let store = makeHistoryStore()
        let menuState = WindowMenuState(history: store)

        store.record(URL(fileURLWithPath: "/c"))

        await waitUntil { menuState.recentLocations.first == URL(fileURLWithPath: "/c") }
        XCTAssertEqual(menuState.recentLocations.first, URL(fileURLWithPath: "/c"))
    }

    func testNavigationUpdatesNavigationMirrors() async {
        let store = makeHistoryStore()
        let (menuState, windowViewModel) = makeConfigured(history: store)
        let flvm = try? XCTUnwrap(windowViewModel.activeTab?.fileListViewModel)

        XCTAssertFalse(menuState.canGoForward)

        await flvm?.navigate(to: tempRoot).value
        await flvm?.navigate(to: tempChild).value

        await waitUntil { menuState.canGoBack && menuState.canGoUp }
        XCTAssertTrue(menuState.canGoBack)
        XCTAssertTrue(menuState.canGoUp)
        XCTAssertFalse(menuState.canGoForward)

        await flvm?.goBack()?.value
        await waitUntil { menuState.canGoForward }
        XCTAssertTrue(menuState.canGoForward, "goBack should make Forward available in the mirror")
    }

    func testActiveTabSwitchRebindsMirrors() async {
        let store = makeHistoryStore()
        let (menuState, windowViewModel) = makeConfigured(history: store)

        let newTab = windowViewModel.openNewTab(at: tempRoot)
        await newTab.fileListViewModel.navigate(to: tempRoot).value
        await newTab.fileListViewModel.navigate(to: tempChild).value

        await waitUntil { menuState.fileListViewModel === newTab.fileListViewModel && menuState.canGoBack }
        XCTAssertTrue(menuState.fileListViewModel === newTab.fileListViewModel)
        XCTAssertTrue(menuState.canGoBack)
    }

    func testLayoutMirrorsFollowTheWindowLayout() async {
        let (menuState, windowViewModel) = makeConfigured(history: makeHistoryStore())
        XCTAssertTrue(menuState.showsInspector)

        windowViewModel.layout.set(\.showsInspector, false)
        windowViewModel.layout.set(\.showsHierarchy, false)

        await waitUntil { !menuState.showsInspector && !menuState.showsHierarchy }
        XCTAssertFalse(menuState.showsInspector)
        XCTAssertFalse(menuState.showsHierarchy)
    }

    func testLayoutMirrorsDoNotRepublishForDraggedSizes() async {
        let (menuState, windowViewModel) = makeConfigured(history: makeHistoryStore())
        // Let configure's own initial mirror updates land first.
        try? await Task.sleep(nanoseconds: 200_000_000)
        var publishCount = 0
        let cancellable = menuState.objectWillChange.sink { publishCount += 1 }

        windowViewModel.layout.recordSize(\.inspectorWidth, 333)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(publishCount, 0)
        cancellable.cancel()
    }

    func testEjectMirrorFollowsTheActiveTabsRoot() async {
        let (menuState, windowViewModel) = makeConfigured(history: makeHistoryStore())
        let usb = makeTestVolume(name: "USB", path: "/Volumes/USB", isEjectable: true)
        destinations.applyVolumes([usb])

        windowViewModel.activeTab?.hierarchyRoot = HierarchyRoot(url: usb.url, name: "USB", kind: .volume)

        await waitUntil { menuState.activeRootIsEjectable }
        XCTAssertTrue(menuState.activeRootIsEjectable)

        windowViewModel.activeTab?.hierarchyRoot = HierarchyRoot(url: tempRoot, name: "tmp", kind: .pinned)
        await waitUntil { !menuState.activeRootIsEjectable }
        XCTAssertFalse(menuState.activeRootIsEjectable)
    }
}
