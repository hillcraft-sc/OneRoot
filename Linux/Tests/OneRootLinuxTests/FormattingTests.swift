import XCTest
@testable import OneRootLinux

final class FormattingTests: XCTestCase {
    func testSummaryWithoutSelection() {
        XCTAssertEqual(Formatting.summary(items: 6, folders: 1, selected: 0), "6 items, 1 folder, 5 files")
    }

    func testSummaryWithSelection() {
        XCTAssertEqual(Formatting.summary(items: 2, folders: 0, selected: 1), "1 of 2 items, 0 folders, 2 files")
    }

    func testSingularItem() {
        XCTAssertEqual(Formatting.summary(items: 1, folders: 0, selected: 0), "1 item, 0 folders, 1 file")
    }

    func testDateOfNilIsEmpty() {
        XCTAssertEqual(Formatting.date(nil), "")
    }
}
