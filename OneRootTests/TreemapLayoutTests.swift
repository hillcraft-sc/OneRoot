import XCTest
@testable import OneRoot

final class TreemapLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 300)

    func testAreasAreProportionalAndFillTheBounds() {
        let values: [Double] = [50, 25, 12, 8, 5]
        let rects = TreemapLayout.rects(for: values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            XCTAssertEqual(Double(rect.width * rect.height), value / total * Double(bounds.width * bounds.height), accuracy: 1)
            XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect), "\(rect)")
        }
    }

    func testRectanglesDontOverlap() {
        let rects = TreemapLayout.rects(for: [40, 30, 10, 10, 5, 3, 2], in: bounds)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.5, "\(i) and \(j) overlap")
            }
        }
    }

    func testZeroValuesGetNoRectangle() {
        let rects = TreemapLayout.rects(for: [10, 0, 5], in: bounds)
        XCTAssertEqual(rects[1], .zero)
        XCTAssertGreaterThan(rects[0].width, 0)
    }

    func testEmptyOrZeroSizedInput() {
        XCTAssertTrue(TreemapLayout.rects(for: [], in: bounds).isEmpty)
        XCTAssertEqual(TreemapLayout.rects(for: [1, 2], in: .zero), [.zero, .zero])
    }
}
