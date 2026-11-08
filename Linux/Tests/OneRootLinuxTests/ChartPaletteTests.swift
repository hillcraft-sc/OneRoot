import XCTest
@testable import OneRootLinux

final class ChartPaletteTests: XCTestCase {
    func testSeriesAreNeverCycled() {
        XCTAssertEqual(ChartPalette.series(at: 0), .series(0))
        XCTAssertEqual(ChartPalette.series(at: 7), .series(7))
        XCTAssertEqual(ChartPalette.series(at: 8), .neutral)
    }

    func testRampSpreadsAcrossTheSteps() {
        XCTAssertEqual(ChartPalette.rampPosition(step: 0, of: 4), 0)
        XCTAssertEqual(ChartPalette.rampPosition(step: 3, of: 4), 3)
        XCTAssertEqual(ChartPalette.rampPosition(step: 0, of: 1), 0)
        XCTAssertEqual(ChartPalette.rampPosition(step: 1, of: 2), 3)
    }

    func testEveryClassNameHasARule() {
        let css = ChartPalette.css
        for dark in [false, true] {
            for color in [ChartPalette.Color.series(0), .series(7), .ordinal(step: 2, of: 4), .neutral] {
                XCTAssertTrue(css.contains(".\(ChartPalette.className(color, dark: dark)) {"), "\(color) \(dark)")
            }
        }
    }

    func testLightAndDarkDiffer() {
        XCTAssertNotEqual(ChartPalette.hex(.series(0), dark: false), ChartPalette.hex(.series(0), dark: true))
        XCTAssertEqual(ChartPalette.hex(.neutral, dark: false), 0xb4b2ac)
    }
}
