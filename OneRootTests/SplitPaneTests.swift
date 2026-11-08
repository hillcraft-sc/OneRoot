import XCTest
@testable import OneRoot

@MainActor
final class SplitPaneTests: XCTestCase {
    private var left: URL!
    private var right: URL!

    override func setUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        left = root.appendingPathComponent("Left", isDirectory: true)
        right = root.appendingPathComponent("Right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: left.deletingLastPathComponent())
    }

    /// A window whose active tab is split, left pane at `left`, right pane at
    /// `right`, focus on the left.
    private func splitWindow() async -> (WindowViewModel, Tab) {
        let window = WindowViewModel()
        let tab = try! XCTUnwrap(window.activeTab)
        await tab.primary.navigate(to: left).value
        window.toggleSplitActiveTab()
        await tab.secondary?.navigate(to: right).value
        return (window, tab)
    }

    /// View ▸ Refresh: both panes pick up changes nothing reported.
    func testRefreshRereadsBothPanes() async throws {
        let (_, tab) = await splitWindow()
        try "x".write(to: left.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: right.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        for task in tab.refresh() { await task.value }

        XCTAssertEqual(tab.primary.items.map(\.name), ["a.txt"])
        XCTAssertEqual(tab.secondary?.items.map(\.name), ["b.txt"])
    }

    func testSplitOpensASecondPaneAtTheSameFolderAndKeepsFocus() async throws {
        let window = WindowViewModel()
        let tab = try XCTUnwrap(window.activeTab)
        await tab.primary.navigate(to: left).value

        window.toggleSplitActiveTab()

        let secondary = try XCTUnwrap(tab.secondary)
        XCTAssertTrue(tab.isSplit)
        XCTAssertEqual(secondary.currentDirectory, left, "starts where you were")
        XCTAssertFalse(secondary === tab.primary, "its own pane, with its own history")
        XCTAssertTrue(tab.fileListViewModel === tab.primary, "focus stays put")
        XCTAssertTrue(tab.otherPane === secondary)
    }

    func testFocusDecidesWhichPaneIsCurrent() async {
        let (_, tab) = await splitWindow()

        tab.focus(.secondary)

        XCTAssertTrue(tab.fileListViewModel === tab.secondary)
        XCTAssertTrue(tab.otherPane === tab.primary)
        XCTAssertEqual(tab.fileListViewModel.currentDirectory, right)
    }

    func testUnsplitKeepsTheFocusedPane() async {
        let (window, tab) = await splitWindow()
        tab.focus(.secondary)

        window.toggleSplitActiveTab()

        XCTAssertFalse(tab.isSplit)
        XCTAssertNil(tab.otherPane)
        XCTAssertEqual(tab.fileListViewModel.currentDirectory, right, "you stay in the folder you were working in")
        XCTAssertEqual(tab.focusedPane, .primary)
    }

    func testSwapPanesTradesSidesAndFocusFollowsThePane() async {
        let (_, tab) = await splitWindow()
        let leftPane = tab.primary
        let rightPane = tab.secondary

        tab.swapPanes()

        XCTAssertTrue(tab.primary === rightPane)
        XCTAssertTrue(tab.secondary === leftPane)
        XCTAssertTrue(tab.fileListViewModel === leftPane, "you keep working in the same pane, now on the right")
        XCTAssertEqual(tab.focusedPane, .secondary)
    }

    func testDetachingAPaneLeavesTheOtherAsASinglePaneTab() async throws {
        let (_, tab) = await splitWindow()
        let leftPane = tab.primary
        let rightPane = try XCTUnwrap(tab.secondary)

        let removed = tab.detach(.primary)

        XCTAssertTrue(removed === leftPane)
        XCTAssertFalse(tab.isSplit)
        XCTAssertTrue(tab.primary === rightPane)
        XCTAssertTrue(tab.fileListViewModel === rightPane)
    }

    func testDetachingFromAnUnsplitTabDoesNothing() {
        let tab = Tab(fileListViewModel: FileListViewModel())

        XCTAssertNil(tab.detach(.primary))
        XCTAssertFalse(tab.isSplit)
    }

    func testFocusingTheSecondaryPaneOfAnUnsplitTabDoesNothing() {
        let tab = Tab(fileListViewModel: FileListViewModel())

        tab.focus(.secondary)

        XCTAssertEqual(tab.focusedPane, .primary)
    }

    func testCopyToOtherPaneCopiesTheSelectionAcross() async throws {
        let (window, tab) = await splitWindow()
        try "x".write(to: left.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await tab.primary.refresh()?.value
        tab.primary.updateSelection(tab.primary.items)

        await window.sendSelectionToOtherPane(move: false)?.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: right.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: left.appendingPathComponent("a.txt").path))
    }

    func testMoveToOtherPaneGoesTheOtherWayWhenTheRightPaneHasFocus() async throws {
        let (window, tab) = await splitWindow()
        try "x".write(to: right.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let rightPane = try XCTUnwrap(tab.secondary)
        await rightPane.refresh()?.value
        rightPane.updateSelection(rightPane.items)
        tab.focus(.secondary)

        await window.sendSelectionToOtherPane(move: true)?.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: left.appendingPathComponent("b.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: right.appendingPathComponent("b.txt").path))
    }

    func testSendingWithoutASplitDoesNothing() async throws {
        let window = WindowViewModel()
        let tab = try XCTUnwrap(window.activeTab)
        await tab.primary.navigate(to: left).value
        try "x".write(to: left.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await tab.primary.refresh()?.value
        tab.primary.updateSelection(tab.primary.items)

        XCTAssertNil(window.sendSelectionToOtherPane(move: false))
    }
}
