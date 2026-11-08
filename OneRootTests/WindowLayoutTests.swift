import XCTest
import Observation
@testable import OneRoot

final class WindowLayoutTests: XCTestCase {
    private var everything: WindowLayout {
        var layout = WindowLayout()
        layout.showsDestinations = true
        layout.showsHierarchy = true
        layout.showsInspector = true
        return layout
    }

    func testAWideWindowShowsEverythingChosen() {
        let fitted = everything.fitted(to: 1600)

        XCTAssertTrue(fitted.showsDestinations)
        XCTAssertTrue(fitted.showsHierarchy)
        XCTAssertTrue(fitted.showsInspector)
    }

    func testTheInspectorGivesWayFirstThenTheHierarchyThenDestinations() {
        // Minimums: list 360, destinations 160, hierarchy 160, Inspector 220.
        let noInspector = everything.fitted(to: 700)
        XCTAssertTrue(noInspector.showsDestinations)
        XCTAssertTrue(noInspector.showsHierarchy)
        XCTAssertFalse(noInspector.showsInspector)

        let listAndDestinations = everything.fitted(to: 600)
        XCTAssertTrue(listAndDestinations.showsDestinations)
        XCTAssertFalse(listAndDestinations.showsHierarchy)

        let listOnly = everything.fitted(to: 400)
        XCTAssertFalse(listOnly.showsDestinations)
    }

    func testFittingNeverShowsAPaneThatWasHidden() {
        var layout = WindowLayout()
        layout.showsHierarchy = false

        XCTAssertFalse(layout.fitted(to: 5000).showsHierarchy)
    }

    func testFittingKeepsTheRestOfTheLayout() {
        var layout = everything
        layout.hierarchyWidth = 333

        XCTAssertEqual(layout.fitted(to: 400).hierarchyWidth, 333)
    }

    func testClampedPullsSizesIntoRange() {
        var layout = WindowLayout()
        layout.inspectorWidth = 5
        layout.workspaceHeight = 99_999

        XCTAssertEqual(layout.clamped.inspectorWidth, WindowLayout.inspectorWidthRange.lowerBound)
        XCTAssertEqual(layout.clamped.workspaceHeight, WindowLayout.workspaceHeightRange.upperBound)
    }

    func testDecodingFillsMissingKeysWithDefaults() throws {
        let layout = try JSONDecoder().decode(WindowLayout.self, from: Data(#"{"version":3,"showsInspector":false}"#.utf8))

        XCTAssertFalse(layout.showsInspector)
        XCTAssertEqual(layout.hierarchyWidth, WindowLayout().hierarchyWidth)
        XCTAssertEqual(layout.workspaceTool, .fileOperations)
    }

    func testAVersion2LayoutIsKeptWithTheToolCardsHidden() throws {
        let saved = #"{"version":2,"showsInspector":false,"inspectorWidth":398,"isWorkspaceExpanded":true}"#
        let layout = try JSONDecoder().decode(WindowLayout.self, from: Data(saved.utf8))

        XCTAssertFalse(layout.showsInspector, "the user's own choices survive")
        XCTAssertEqual(layout.inspectorWidth, 398)
        XCTAssertFalse(layout.isWorkspaceExpanded)
    }

    func testToolCardsStartHidden() {
        XCTAssertFalse(WindowLayout().isWorkspaceExpanded)
    }

    func testDecodingAnUnknownToolFallsBackToTheDefault() throws {
        let layout = try JSONDecoder().decode(WindowLayout.self, from: Data(#"{"version":3,"workspaceTool":"visualize"}"#.utf8))

        XCTAssertEqual(layout.workspaceTool, .fileOperations)
    }
}

final class WindowLayoutServiceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testDefaultsWhenNothingSaved() {
        XCTAssertEqual(WindowLayoutService(defaults: makeDefaults()).load(), WindowLayout())
    }

    func testRoundTrip() {
        let service = WindowLayoutService(defaults: makeDefaults())
        var layout = WindowLayout()
        layout.showsHierarchy = false
        layout.destinationsWidth = 222

        service.save(layout)

        XCTAssertEqual(service.load(), layout)
    }

    func testTheOldPreviewPaneWidthCarriesOverToTheInspector() {
        let defaults = makeDefaults()
        defaults.set(350.0, forKey: "com.oneroot.previewPaneWidth")

        let layout = WindowLayoutService(defaults: defaults).load()

        XCTAssertTrue(layout.showsInspector)
        XCTAssertEqual(layout.inspectorWidth, 350)
    }

    func testALayoutSavedBeforeTheOneRootDefaultsIsReplacedByThem() throws {
        // Version 1 had no `version` key, and the Inspector off.
        let old = #"{"showsInspector":false,"isWorkspaceExpanded":false,"hierarchyWidth":333}"#
        let layout = try JSONDecoder().decode(WindowLayout.self, from: Data(old.utf8))

        XCTAssertEqual(layout, WindowLayout())
    }
}

@MainActor
final class WindowLayoutModelTests: XCTestCase {
    func testVisibleChangesPublish() {
        let model = WindowLayoutModel(layout: WindowLayout())
        var notified = false
        withObservationTracking { _ = model.layout } onChange: { notified = true }
        model.set(\.showsInspector, true) // unchanged
        XCTAssertFalse(notified)

        model.toggle(\.showsInspector)

        XCTAssertTrue(notified)
        XCTAssertFalse(model.layout.showsInspector)
    }

    func testDraggedSizesAreStoredWithoutPublishing() {
        let model = WindowLayoutModel(layout: WindowLayout())
        var notified = false
        withObservationTracking { _ = model.layout } onChange: { notified = true }

        model.recordSize(\.hierarchyWidth, 260)

        XCTAssertFalse(notified)
        XCTAssertEqual(model.layout.hierarchyWidth, 260)
    }

    func testResetRestoresTheDefaults() {
        var custom = WindowLayout()
        custom.showsInspector = false
        custom.hierarchyWidth = 400
        let model = WindowLayoutModel(layout: custom)

        model.reset()

        XCTAssertEqual(model.layout, WindowLayout())
    }

    func testDraggedSizesAreClamped() {
        let model = WindowLayoutModel(layout: WindowLayout())

        model.recordSize(\.hierarchyWidth, 10)

        XCTAssertEqual(model.layout.hierarchyWidth, WindowLayout.hierarchyWidthRange.lowerBound)
    }
}

#if !SWIFT_PACKAGE // CardStatusBar is a SwiftUI view: Mac app only
final class CardStatusBarTests: XCTestCase {
    func testSummaryPluralizes() {
        XCTAssertEqual(CardStatusBar.summary(items: 1, folders: 0, selected: 0), "1 item, 0 folders, 1 file")
        XCTAssertEqual(CardStatusBar.summary(items: 6, folders: 1, selected: 0), "6 items, 1 folder, 5 files")
        XCTAssertEqual(CardStatusBar.summary(items: 2, folders: 0, selected: 1), "1 of 2 items, 0 folders, 2 files")
    }
}
#endif

final class VolumeSpaceLevelTests: XCTestCase {
    func testColorsChangeAtEightyAndNinetyPercent() {
        func level(usedPercent: Int64) -> VolumeSpace.Level {
            VolumeSpace(availableCapacity: 100 - usedPercent, totalCapacity: 100).level
        }
        XCTAssertEqual(level(usedPercent: 79), .normal)
        XCTAssertEqual(level(usedPercent: 80), .nearlyFull)
        XCTAssertEqual(level(usedPercent: 89), .nearlyFull)
        XCTAssertEqual(level(usedPercent: 90), .full)
        XCTAssertEqual(VolumeSpace(availableCapacity: 0, totalCapacity: 0).level, .normal)
        XCTAssertNil(VolumeSpace.Level.normal.description)
    }
}
