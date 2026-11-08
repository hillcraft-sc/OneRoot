#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import OneRoot

final class SessionServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "SessionServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func pane(_ path: String) -> SavedPane {
        SavedPane(path: path, sortField: FileColumn.name.rawValue, sortAscending: true)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testSaveAndLoadRoundTrip() {
        let service = SessionService(defaults: defaults)
        let session = SavedSession(windows: [
            SavedWindow(frame: CGRect(x: 10, y: 20, width: 800, height: 600), tabs: [
                SavedTab(primary: pane("/a"), secondary: pane("/b"), secondaryHasFocus: true),
            ], activeTabIndex: 0),
        ])

        service.save(session)

        XCTAssertEqual(service.load(), session)
    }

    func testEnabledByDefaultAndTurningOffForgetsTheSession() {
        let service = SessionService(defaults: defaults)
        XCTAssertTrue(service.isEnabled)
        service.save(SavedSession(windows: []))

        service.setEnabled(false)

        XCTAssertNil(service.load())
        service.save(SavedSession(windows: []))
        XCTAssertNil(defaults.data(forKey: "com.oneroot.savedSession"), "nothing is saved while off")
    }

    func testALaunchArgumentStyleStringValueTurnsItOff() {
        // `-com.oneroot.restoreSession NO` stores the *string* "NO".
        defaults.set("NO", forKey: "com.oneroot.restoreSession")
        XCTAssertFalse(SessionService(defaults: defaults).isEnabled)

        defaults.set("YES", forKey: "com.oneroot.restoreSession")
        XCTAssertTrue(SessionService(defaults: defaults).isEnabled)
    }

    func testMissingFoldersFallBackHomeAndMissingSplitPanesAreDropped() {
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [
                SavedTab(primary: pane("/gone"), secondary: nil, secondaryHasFocus: false),
                SavedTab(primary: pane("/here"), secondary: pane("/gone-too"), secondaryHasFocus: true),
            ], activeTabIndex: 1),
        ])

        let clean = SessionService.sanitized(session, folderExists: { $0 == "/here" }, fallbackFolder: "/home", screens: [screen])

        let tabs = clean.windows[0].tabs
        XCTAssertEqual(tabs[0].primary.path, "/home")
        XCTAssertEqual(tabs[1].primary.path, "/here")
        XCTAssertNil(tabs[1].secondary)
        XCTAssertFalse(tabs[1].secondaryHasFocus)
    }

    func testFramesOffEveryScreenAreDropped() {
        let session = SavedSession(windows: [
            SavedWindow(frame: CGRect(x: 100, y: 100, width: 800, height: 600), tabs: [SavedTab(primary: pane("/a"), secondary: nil, secondaryHasFocus: false)], activeTabIndex: 0),
            SavedWindow(frame: CGRect(x: 3000, y: 100, width: 800, height: 600), tabs: [SavedTab(primary: pane("/a"), secondary: nil, secondaryHasFocus: false)], activeTabIndex: 0),
        ])

        let clean = SessionService.sanitized(session, folderExists: { _ in true }, fallbackFolder: "/home", screens: [screen])

        XCTAssertNotNil(clean.windows[0].frame)
        XCTAssertNil(clean.windows[1].frame, "was on a monitor that's gone")
    }

    func testASessionSavedBeforeLayoutsAndRootsStillLoads() throws {
        // What an older build wrote: no `layout`, no `hierarchyRoot`.
        let json = """
        {"windows":[{"tabs":[{"primary":{"path":"/a","sortField":"name","sortAscending":true},"secondaryHasFocus":false}],"activeTabIndex":0}]}
        """
        defaults.set(Data(json.utf8), forKey: "com.oneroot.savedSession")

        let session = try XCTUnwrap(SessionService(defaults: defaults).load())

        XCTAssertNil(session.windows[0].layout)
        XCTAssertNil(session.windows[0].tabs[0].hierarchyRoot)
        XCTAssertNil(session.windows[0].tabs[0].inspectorSection)
        XCTAssertEqual(session.windows[0].tabs[0].primary.path, "/a")
    }

    func testInspectorSectionRoundTrips() {
        let service = SessionService(defaults: defaults)
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [
                SavedTab(primary: pane("/a"), secondary: nil, secondaryHasFocus: false, inspectorSection: .permissions),
                SavedTab(primary: pane("/b"), secondary: nil, secondaryHasFocus: false, inspectorSection: .moreInfo),
            ], activeTabIndex: 0),
        ])

        service.save(session)

        XCTAssertEqual(service.load()?.windows[0].tabs.map(\.inspectorSection), [.permissions, .moreInfo])
    }

    func testWorkspaceRoundTrips() {
        let service = SessionService(defaults: defaults)
        let id = UUID()
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [
                SavedTab(primary: pane("/a"), secondary: nil, secondaryHasFocus: false, workspaceID: id),
            ], activeTabIndex: 0),
        ])

        service.save(session)

        XCTAssertEqual(service.load()?.windows[0].tabs[0].workspaceID, id)
    }

    func testLayoutAndHierarchyRootRoundTrip() {
        let service = SessionService(defaults: defaults)
        var layout = WindowLayout()
        layout.showsInspector = true
        layout.hierarchyWidth = 250
        layout.isWorkspaceExpanded = true
        let root = HierarchyRoot(url: URL(fileURLWithPath: "/a"), name: "a", kind: .pinned)
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [
                SavedTab(primary: pane("/a/b"), secondary: nil, secondaryHasFocus: false, hierarchyRoot: root),
            ], activeTabIndex: 0, layout: layout),
        ])

        service.save(session)

        XCTAssertEqual(service.load(), session)
    }

    func testAHierarchyRootThatIsGoneIsDropped() {
        let root = HierarchyRoot(url: URL(fileURLWithPath: "/gone"), name: "gone", kind: .volume)
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [
                SavedTab(primary: pane("/here"), secondary: nil, secondaryHasFocus: false, hierarchyRoot: root),
            ], activeTabIndex: 0),
        ])

        let clean = SessionService.sanitized(session, folderExists: { $0 == "/here" }, fallbackFolder: "/home", screens: [screen])

        XCTAssertNil(clean.windows[0].tabs[0].hierarchyRoot)
    }

    func testEmptyWindowsDroppedAndActiveIndexClamped() {
        let session = SavedSession(windows: [
            SavedWindow(frame: nil, tabs: [], activeTabIndex: 0),
            SavedWindow(frame: nil, tabs: [SavedTab(primary: pane("/a"), secondary: nil, secondaryHasFocus: false)], activeTabIndex: 7),
        ])

        let clean = SessionService.sanitized(session, folderExists: { _ in true }, fallbackFolder: "/home", screens: [screen])

        XCTAssertEqual(clean.windows.count, 1)
        XCTAssertEqual(clean.windows[0].activeTabIndex, 0)
    }
}

@MainActor
final class WindowSessionTests: XCTestCase {
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

    func testRestoresTabsSplitsSortAndActiveTab() async throws {
        let saved = SavedWindow(frame: nil, tabs: [
            SavedTab(primary: SavedPane(path: left.path, sortField: FileColumn.name.rawValue, sortAscending: true), secondary: nil, secondaryHasFocus: false),
            SavedTab(
                primary: SavedPane(path: left.path, sortField: FileColumn.size.rawValue, sortAscending: false),
                secondary: SavedPane(path: right.path, sortField: FileColumn.name.rawValue, sortAscending: true),
                secondaryHasFocus: true
            ),
        ], activeTabIndex: 1)

        let window = WindowViewModel(restoring: saved)

        XCTAssertEqual(window.tabs.count, 2)
        let active = try XCTUnwrap(window.activeTab)
        XCTAssertTrue(active === window.tabs[1])
        XCTAssertTrue(active.isSplit)
        XCTAssertEqual(active.focusedPane, .secondary)
        XCTAssertEqual(active.primary.sortField, .size)
        XCTAssertEqual(active.primary.sortDirection, .descending)
        XCTAssertEqual(active.secondary?.currentDirectory?.path, right.path)
    }

    func testSavedStateRoundTripsThroughRestore() async throws {
        let window = WindowViewModel()
        let tab = try XCTUnwrap(window.activeTab)
        await tab.primary.navigate(to: left).value
        tab.primary.setSort(field: .dateModified)
        window.toggleSplitActiveTab()
        await tab.secondary?.navigate(to: right).value
        tab.focus(.secondary)

        let state = window.savedState(frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let restored = WindowViewModel(restoring: state).savedState(frame: CGRect(x: 1, y: 2, width: 3, height: 4))

        XCTAssertEqual(state.tabs.first?.primary.path, left.path)
        XCTAssertEqual(state.tabs.first?.secondary?.path, right.path)
        XCTAssertEqual(state.tabs.first?.primary.sortField, FileColumn.dateModified.rawValue)
        XCTAssertEqual(restored, state)
    }

    func testHierarchyRootsAndLayoutSurviveARestore() throws {
        let window = WindowViewModel()
        let tab = try XCTUnwrap(window.activeTab)
        tab.hierarchyRoot = HierarchyRoot(url: left, name: "Left", kind: .pinned)
        window.layout.set(\.showsInspector, true)
        window.layout.recordSize(\.hierarchyWidth, 300)

        let restored = WindowViewModel(restoring: window.savedState(frame: nil))

        XCTAssertEqual(restored.activeTab?.hierarchyRoot, tab.hierarchyRoot)
        XCTAssertTrue(restored.layout.layout.showsInspector)
        XCTAssertEqual(restored.layout.layout.hierarchyWidth, 300)
    }
}
