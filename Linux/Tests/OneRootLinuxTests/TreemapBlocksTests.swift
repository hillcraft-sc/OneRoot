import XCTest
@testable import OneRootLinux
@testable import OneRoot

final class TreemapBlocksTests: XCTestCase {
    private func entry(_ name: String, _ size: Int64, folder: Bool = false) -> StorageEntry {
        StorageEntry(url: URL(fileURLWithPath: "/t/\(name)"), isDirectory: folder, size: size, fileCount: 1)
    }

    func testSmallItemsFoldIntoOther() {
        let children = [entry("a", 900), entry("b", 90), entry("c", 5), entry("d", 5)]
        let blocks = TreemapBlocks.blocks(children: children, totalSize: 1000)
        XCTAssertEqual(blocks.map(\.title), ["a", "b", "Other (2)"])
        XCTAssertEqual(blocks.last?.size, 10)
        XCTAssertNil(blocks.last?.entry)
    }

    func testAtMostFourteenBlocksPlusOther() {
        let children = (0..<30).map { entry("f\($0)", Int64(1000 - $0)) }
        let blocks = TreemapBlocks.blocks(children: children, totalSize: children.reduce(0) { $0 + $1.size })
        XCTAssertEqual(blocks.count, TreemapBlocks.maxBlocks + 1)
        XCTAssertEqual(blocks.last?.title, "Other (16)")
    }

    func testEmptyAndZeroSizedItemsMakeNoBlocks() {
        XCTAssertTrue(TreemapBlocks.blocks(children: [], totalSize: 0).isEmpty)
        XCTAssertTrue(TreemapBlocks.blocks(children: [entry("z", 0)], totalSize: 0).isEmpty)
    }

    func testPercentText() {
        XCTAssertEqual(TreemapBlocks.percent(500, of: 1000), "50%")
        XCTAssertEqual(TreemapBlocks.percent(1, of: 1000), "<1%")
        XCTAssertEqual(TreemapBlocks.percent(1, of: 0), "")
    }
}

final class StackedBarWidthsTests: XCTestCase {
    func testWidthsAreProportionalAndLeaveRoomForGaps() {
        let widths = StackedBarView.widths(for: [750, 250], in: 502, gap: 2)
        XCTAssertEqual(widths[0], 375, accuracy: 0.01)
        XCTAssertEqual(widths[1], 125, accuracy: 0.01)
    }

    func testTinyAndEmptyGroupsKeepAVisibleSliverOrNone() {
        let widths = StackedBarView.widths(for: [1_000_000, 1, 0], in: 400)
        XCTAssertEqual(widths[1], 2)
        XCTAssertEqual(widths[2], 0)
        XCTAssertEqual(StackedBarView.widths(for: [0, 0], in: 400), [0, 0])
    }
}
