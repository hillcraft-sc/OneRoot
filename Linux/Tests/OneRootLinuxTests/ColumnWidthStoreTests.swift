import XCTest
@testable import OneRoot
@testable import OneRootLinux

@MainActor
final class ColumnWidthStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "ColumnWidthStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testWidthIsRememberedAndClamped() {
        let defaults = makeDefaults()
        let store = ColumnWidthStore(defaults: defaults)
        XCTAssertNil(store.width(for: .size))
        store.set(150, for: .size)
        store.set(5000, for: .dateModified)
        XCTAssertEqual(ColumnWidthStore(defaults: defaults).width(for: .size), 150)
        XCTAssertEqual(ColumnWidthStore(defaults: defaults).width(for: .dateModified), 1200)
    }

    func testNameHasNoRememberedWidth() {
        let store = ColumnWidthStore(defaults: makeDefaults())
        store.set(300, for: .name)
        XCTAssertNil(store.width(for: .name))
    }
}

final class QuickLookStepTests: XCTestCase {
    func testSteppingStopsAtTheEnds() {
        XCTAssertEqual(QuickLookWindow.stepped(0, by: -1, count: 3), 0)
        XCTAssertEqual(QuickLookWindow.stepped(1, by: 1, count: 3), 2)
        XCTAssertEqual(QuickLookWindow.stepped(2, by: 1, count: 3), 2)
        XCTAssertEqual(QuickLookWindow.stepped(0, by: 1, count: 0), 0)
    }
}
