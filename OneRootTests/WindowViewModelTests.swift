import XCTest
@testable import OneRoot

@MainActor
final class WindowViewModelTests: XCTestCase {
    private var tempA: URL!
    private var tempB: URL!

    override func setUp() async throws {
        tempA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        tempB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempB, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempA)
        try? FileManager.default.removeItem(at: tempB)
    }

    /// Every `WindowViewModel` here gets its own isolated navigation
    /// history, so tab tests don't write temp-dir paths into the real
    /// app's Recent Locations (`UserDefaults.standard`).
    private func makeWindowViewModel(startingTab: Tab? = nil) -> WindowViewModel {
        WindowViewModel(
            navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)),
            startingTab: startingTab
        )
    }

    func testInitCreatesOneActiveTab() {
        let windowViewModel = makeWindowViewModel()

        XCTAssertEqual(windowViewModel.tabs.count, 1)
        XCTAssertEqual(windowViewModel.activeTab?.id, windowViewModel.tabs.first?.id)
    }

    func testOpenNewTabAddsAndActivatesTab() {
        let windowViewModel = makeWindowViewModel()

        let newTab = windowViewModel.openNewTab(at: tempA)

        XCTAssertEqual(windowViewModel.tabs.count, 2)
        XCTAssertEqual(windowViewModel.activeTabID, newTab.id)
        XCTAssertEqual(windowViewModel.activeTab?.fileListViewModel.currentDirectory, tempA)
    }

    func testOpenNewTabCanBeBackground() {
        let windowViewModel = makeWindowViewModel()
        let originalActiveID = windowViewModel.activeTabID

        let newTab = windowViewModel.openNewTab(at: tempA, makeActive: false)

        XCTAssertEqual(windowViewModel.tabs.count, 2)
        XCTAssertEqual(windowViewModel.activeTabID, originalActiveID)
        XCTAssertNotEqual(windowViewModel.activeTabID, newTab.id)
    }

    func testCloseTabActivatesNeighbor() {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let secondTab = windowViewModel.openNewTab(at: tempA)
        let thirdTab = windowViewModel.openNewTab(at: tempB)
        windowViewModel.selectTab(secondTab)

        windowViewModel.closeTab(secondTab)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [firstTab.id, thirdTab.id])
        XCTAssertEqual(windowViewModel.activeTabID, thirdTab.id)
    }

    func testClosingInactiveTabDoesNotChangeActiveTab() {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let secondTab = windowViewModel.openNewTab(at: tempA, makeActive: false)

        windowViewModel.closeTab(secondTab)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [firstTab.id])
        XCTAssertEqual(windowViewModel.activeTabID, firstTab.id)
    }

    func testClosingLastTabLeavesNoTabs() {
        let windowViewModel = makeWindowViewModel()
        let onlyTab = windowViewModel.tabs[0]

        windowViewModel.closeTab(onlyTab)

        XCTAssertTrue(windowViewModel.tabs.isEmpty)
        XCTAssertNil(windowViewModel.activeTabID)
    }

    func testCloseOtherTabsKeepsJustThatOneActive() {
        let windowViewModel = makeWindowViewModel()
        let keep = windowViewModel.openNewTab(at: tempA)
        windowViewModel.openNewTab(at: tempB)
        windowViewModel.selectTab(windowViewModel.tabs[0])

        windowViewModel.closeOtherTabs(keeping: keep)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [keep.id])
        XCTAssertEqual(windowViewModel.activeTabID, keep.id)
    }

    func testCloseTabsToTheRightMovesActiveOnlyIfItWasClosed() {
        let windowViewModel = makeWindowViewModel()
        let first = windowViewModel.tabs[0]
        windowViewModel.openNewTab(at: tempA)
        let third = windowViewModel.openNewTab(at: tempB)
        XCTAssertTrue(windowViewModel.hasTabs(after: first))
        XCTAssertFalse(windowViewModel.hasTabs(after: third))

        // Active (third) is to the right of first: it goes, first becomes active.
        windowViewModel.closeTabsToTheRight(of: first)
        XCTAssertEqual(windowViewModel.tabs.map(\.id), [first.id])
        XCTAssertEqual(windowViewModel.activeTabID, first.id)

        // Active left of the anchor stays active.
        let again = makeWindowViewModel()
        let a = again.tabs[0]
        let b = again.openNewTab(at: tempA)
        again.openNewTab(at: tempB)
        again.selectTab(a)
        again.closeTabsToTheRight(of: b)
        XCTAssertEqual(again.tabs.count, 2)
        XCTAssertEqual(again.activeTabID, a.id)
    }

    func testNextAndPreviousTabWrapAround() {
        let windowViewModel = makeWindowViewModel()
        let first = windowViewModel.tabs[0]
        windowViewModel.openNewTab(at: tempA)
        let last = windowViewModel.openNewTab(at: tempB)

        windowViewModel.selectAdjacentTab(1)
        XCTAssertEqual(windowViewModel.activeTabID, first.id)
        windowViewModel.selectAdjacentTab(-1)
        XCTAssertEqual(windowViewModel.activeTabID, last.id)
    }

    func testSelectTabChangesActiveTab() {
        let windowViewModel = makeWindowViewModel()
        let secondTab = windowViewModel.openNewTab(at: tempA, makeActive: false)

        XCTAssertNotEqual(windowViewModel.activeTabID, secondTab.id)
        windowViewModel.selectTab(secondTab)
        XCTAssertEqual(windowViewModel.activeTabID, secondTab.id)
    }

    func testTabsHaveIndependentHistory() async {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let homeDirectory = firstTab.fileListViewModel.currentDirectory
        await firstTab.fileListViewModel.navigate(to: tempA).value

        let secondTab = windowViewModel.openNewTab(at: tempB)

        XCTAssertEqual(firstTab.fileListViewModel.currentDirectory, tempA)
        XCTAssertEqual(secondTab.fileListViewModel.currentDirectory, tempB)
        XCTAssertTrue(firstTab.fileListViewModel.canGoBack) // navigated home -> tempA
        XCTAssertFalse(secondTab.fileListViewModel.canGoBack) // only ever navigated once
        XCTAssertNotEqual(homeDirectory, tempA)
    }

    func testMoveTabReordersWithinTheStrip() {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let secondTab = windowViewModel.openNewTab(at: tempA)
        let thirdTab = windowViewModel.openNewTab(at: tempB)

        windowViewModel.moveTab(firstTab, to: 2)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [secondTab.id, thirdTab.id, firstTab.id])
    }

    func testMoveTabClampsAnOutOfRangeDestination() {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let secondTab = windowViewModel.openNewTab(at: tempA)

        windowViewModel.moveTab(firstTab, to: 99)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [secondTab.id, firstTab.id])
    }

    func testDetachTabRemovesItAndActivatesNeighbor() {
        let windowViewModel = makeWindowViewModel()
        let firstTab = windowViewModel.tabs[0]
        let secondTab = windowViewModel.openNewTab(at: tempA)
        windowViewModel.selectTab(secondTab)

        windowViewModel.detachTab(secondTab)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [firstTab.id])
        XCTAssertEqual(windowViewModel.activeTabID, firstTab.id)
    }

    func testDetachingLastTabLeavesWindowEmpty() {
        let windowViewModel = makeWindowViewModel()
        let onlyTab = windowViewModel.tabs[0]

        windowViewModel.detachTab(onlyTab)

        XCTAssertTrue(windowViewModel.tabs.isEmpty)
        XCTAssertNil(windowViewModel.activeTabID)
    }

    func testInsertTabAddsItAtIndexAndActivatesIt() {
        let source = makeWindowViewModel()
        let handedOffTab = source.tabs[0]
        source.detachTab(handedOffTab)
        let destination = makeWindowViewModel()
        let existingTab = destination.tabs[0]

        destination.insertTab(handedOffTab, at: 0)

        XCTAssertEqual(destination.tabs.map(\.id), [handedOffTab.id, existingTab.id])
        XCTAssertEqual(destination.activeTabID, handedOffTab.id)
    }

    func testStartingTabSeedsTheWindowInsteadOfTheDefaultHomeTab() {
        let source = makeWindowViewModel()
        let handedOffTab = source.tabs[0]
        source.detachTab(handedOffTab)

        let windowViewModel = makeWindowViewModel(startingTab: handedOffTab)

        XCTAssertEqual(windowViewModel.tabs.map(\.id), [handedOffTab.id])
        XCTAssertEqual(windowViewModel.activeTabID, handedOffTab.id)
    }
}

@MainActor
final class MoveTabToNewWindowTests: XCTestCase {
    private func windowWithTabs(_ count: Int) -> WindowViewModel {
        let window = WindowViewModel()
        for _ in 1..<count { window.openNewTab(at: FileManager.default.temporaryDirectory) }
        return window
    }

    func testTakesTheActiveTabOutAndLeavesTheOthers() throws {
        let window = windowWithTabs(3)
        window.selectTab(window.tabs[1])
        let active = try XCTUnwrap(window.activeTab)

        let moved = window.detachActiveTabForNewWindow()

        XCTAssertTrue(moved === active)
        XCTAssertEqual(window.tabs.count, 2)
        XCTAssertFalse(window.tabs.contains { $0 === active })
        XCTAssertNotNil(window.activeTab, "another tab becomes active")
    }

    func testAWindowsOnlyTabStaysPut() throws {
        let window = windowWithTabs(1)
        let only = try XCTUnwrap(window.activeTab)

        XCTAssertNil(window.detachActiveTabForNewWindow())

        XCTAssertEqual(window.tabs.count, 1)
        XCTAssertTrue(window.activeTab === only)
    }

    func testASplitTabKeepsBothPanes() throws {
        let window = windowWithTabs(2)
        window.toggleSplitActiveTab()

        let moved = try XCTUnwrap(window.detachActiveTabForNewWindow())

        XCTAssertTrue(moved.isSplit)
    }

    func testTheNewWindowOpensDownAndRightOfTheOne() {
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

        let point = TabHandoffCenter.cascadePoint(from: frame)

        // The new window turns the point back into its top-left: x − 80, y + 20.
        XCTAssertEqual(point.x - 80, frame.minX + 30)
        XCTAssertEqual(point.y + 20, frame.maxY - 30)
    }
}

@MainActor
final class WindowViewModelDestinationTests: XCTestCase {
    private var tempA: URL!

    override func setUp() async throws {
        tempA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempA, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempA)
    }

    private func makeWindowViewModel() -> WindowViewModel {
        WindowViewModel(navigationHistory: NavigationHistoryStore(service: NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)))
    }

    // MARK: Destinations and hierarchy roots

    func testSelectingADestinationRootsTheActiveTabAndGoesThere() async throws {
        let windowViewModel = makeWindowViewModel()
        let tab = try XCTUnwrap(windowViewModel.activeTab)
        let destination = Destination(url: tempA, name: "A", kind: .pinned)

        windowViewModel.selectDestination(destination)

        XCTAssertEqual(tab.hierarchyRoot, destination.hierarchyRoot)
        XCTAssertEqual(tab.fileListViewModel.currentDirectory, tempA)
        XCTAssertEqual(windowViewModel.tabs.count, 1)
    }

    func testSelectingADestinationInANewTabLeavesTheCurrentTabAlone() throws {
        let windowViewModel = makeWindowViewModel()
        let original = try XCTUnwrap(windowViewModel.activeTab)
        let originalRoot = original.hierarchyRoot
        let destination = Destination(url: tempA, name: "A", kind: .pinned)

        windowViewModel.selectDestination(destination, inNewTab: true)

        XCTAssertEqual(windowViewModel.tabs.count, 2)
        XCTAssertEqual(original.hierarchyRoot, originalRoot)
        XCTAssertEqual(windowViewModel.activeTab?.hierarchyRoot, destination.hierarchyRoot)
        XCTAssertEqual(windowViewModel.activeTab?.fileListViewModel.currentDirectory, tempA)
    }

    func testDuplicateTabKeepsTheHierarchyRoot() throws {
        let windowViewModel = makeWindowViewModel()
        let tab = try XCTUnwrap(windowViewModel.activeTab)
        tab.hierarchyRoot = HierarchyRoot(url: tempA, name: "A", kind: .pinned)

        windowViewModel.duplicateActiveTab()

        XCTAssertEqual(windowViewModel.activeTab?.hierarchyRoot, tab.hierarchyRoot)
        XCTAssertFalse(windowViewModel.activeTab === tab)
    }

    // MARK: Dual Pane

    func testDualPaneDoesNotChangeTheToolsPanel() {
        let windowViewModel = makeWindowViewModel()
        windowViewModel.setWorkspaceExpanded(false)

        windowViewModel.toggleSplitActiveTab()

        XCTAssertTrue(windowViewModel.activeTab?.isSplit ?? false)
        XCTAssertFalse(windowViewModel.layout.layout.isWorkspaceExpanded)
    }

    func testCollapsingTheToolsPanelLeavesASplitTabAlone() throws {
        let windowViewModel = makeWindowViewModel()
        windowViewModel.toggleSplitActiveTab()
        let tab = try XCTUnwrap(windowViewModel.activeTab)
        tab.focus(.secondary)
        windowViewModel.setWorkspaceExpanded(true)

        windowViewModel.setWorkspaceExpanded(false)

        XCTAssertTrue(tab.isSplit)
        XCTAssertEqual(tab.focusedPane, .secondary)
    }
}
