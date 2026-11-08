import XCTest
@testable import OneRootLinux

final class HistoryFilterTests: XCTestCase {
    private let entries = [
        URL(fileURLWithPath: "/home/me/Documents"),
        URL(fileURLWithPath: "/home/me/Pictures/Trip"),
        URL(fileURLWithPath: "/srv/data"),
    ]

    func testEmptyQueryKeepsEverythingInOrder() {
        XCTAssertEqual(HistoryWindow.matching(entries, query: ""), entries)
        XCTAssertEqual(HistoryWindow.matching(entries, query: "   "), entries)
    }

    func testMatchesAnywhereInThePathIgnoringCase() {
        XCTAssertEqual(HistoryWindow.matching(entries, query: "PICT").map(\.lastPathComponent), ["Trip"])
        XCTAssertEqual(HistoryWindow.matching(entries, query: "me/").count, 2)
    }

    func testNoMatchGivesNothing() {
        XCTAssertTrue(HistoryWindow.matching(entries, query: "zzz").isEmpty)
    }
}

final class SearchInputHelpersTests: XCTestCase {
    func testParsesAValidDate() {
        let date = SearchInputHelpers.parseDate("2026-03-09")
        XCTAssertNotNil(date)
        XCTAssertEqual(SearchInputHelpers.formatDate(date), "2026-03-09")
    }

    func testRejectsBadDates() {
        for text in ["", "2026-3-9", "2026-13-01", "2026-02-30", "yesterday", "26-03-09"] {
            XCTAssertNil(SearchInputHelpers.parseDate(text), text)
        }
    }

    func testFormatOfNilIsEmpty() {
        XCTAssertEqual(SearchInputHelpers.formatDate(nil), "")
    }
}

final class EditorDetectionTests: XCTestCase {
    func testReadsCategoriesFromTheDesktopEntryOnly() {
        let file = """
        [Desktop Entry]
        Name=Code
        Categories=Utility;TextEditor;Development;IDE;
        [Desktop Action new-window]
        Categories=Ignored;
        """
        XCTAssertEqual(AppChooser.categories(inDesktopFile: file), "Utility;TextEditor;Development;IDE;")
        XCTAssertEqual(AppChooser.categories(inDesktopFile: "[Desktop Entry]\nName=x\n"), "")
    }

    func testEditorsAreTextEditorsOrIDEs() {
        XCTAssertTrue(AppChooser.isEditor(categories: "Utility;TextEditor;"))
        XCTAssertTrue(AppChooser.isEditor(categories: "Development;IDE;"))
        XCTAssertFalse(AppChooser.isEditor(categories: "Network;WebBrowser;"))
        XCTAssertFalse(AppChooser.isEditor(categories: ""))
    }
}
