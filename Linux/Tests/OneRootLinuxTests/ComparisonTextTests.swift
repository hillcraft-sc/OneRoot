import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class ComparisonTextTests: XCTestCase {
    func testLabelsAndClasses() {
        XCTAssertEqual(ComparisonText.label(.same), "")
        XCTAssertEqual(ComparisonText.label(.newerHere), "Newer")
        XCTAssertNil(ComparisonText.cssClass(.same))
        XCTAssertNil(ComparisonText.cssClass(.olderHere))
        XCTAssertEqual(ComparisonText.cssClass(.differs), "oneroot-cmp-differs")
    }

    func testSummary() {
        var result = FolderComparison()
        result.left = ["a": .newerHere, "b": .onlyHere, "c": .onlyHere, "d": .same]
        XCTAssertEqual(ComparisonText.summary(result, onLeft: true), "1 newer \u{00B7} 2 only here")
        XCTAssertEqual(ComparisonText.summary(result, onLeft: false), "nothing newer or extra")
    }

    func testPreviewListsItemsAndNotCopied() {
        let folder = URL(fileURLWithPath: "/tmp/left")
        let plan = PaneComparison.SyncPlan(
            toRight: true,
            items: (1...15).map { folder.appendingPathComponent("f\($0)") },
            statuses: ["f1": .newerHere],
            destination: URL(fileURLWithPath: "/tmp/right"),
            notCopied: ["x", "y"]
        )
        let text = ComparisonText.syncPreview(plan, sourceName: "left", destinationName: "right")
        XCTAssertEqual(text.heading, "Copy 15 items from \u{201C}left\u{201D} to \u{201C}right\u{201D}?")
        XCTAssertTrue(text.body.contains("\u{2022} f1 (Newer)"))
        XCTAssertTrue(text.body.contains("and 3 more"))
        XCTAssertTrue(text.body.contains("Not copied"))
    }

    func testPreviewWithNothingToCopy() {
        let plan = PaneComparison.SyncPlan(toRight: false, items: [], statuses: [:], destination: URL(fileURLWithPath: "/tmp/l"), notCopied: [])
        XCTAssertEqual(ComparisonText.syncPreview(plan, sourceName: "r", destinationName: "l").heading, "Nothing to copy to \u{201C}l\u{201D}")
    }
}
