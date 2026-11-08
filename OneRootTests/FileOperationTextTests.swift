import XCTest
@testable import OneRoot

/// The words the progress panels use, on both platforms.
final class FileOperationTextTests: XCTestCase {
    func testAbbreviatedDurationKeepsTwoUnits() {
        XCTAssertEqual(FileOperationText.abbreviatedDuration(0), "0s")
        XCTAssertEqual(FileOperationText.abbreviatedDuration(45), "45s")
        XCTAssertEqual(FileOperationText.abbreviatedDuration(60), "1m")
        XCTAssertEqual(FileOperationText.abbreviatedDuration(200), "3m 20s")
        XCTAssertEqual(FileOperationText.abbreviatedDuration(3_723), "1h 2m")
        XCTAssertEqual(FileOperationText.abbreviatedDuration(7_200), "2h")
    }

    func testSpokenDurationUsesTheLargestUnit() {
        XCTAssertEqual(FileOperationText.spokenDuration(1.2), "1 second")
        XCTAssertEqual(FileOperationText.spokenDuration(44.6), "45 seconds")
        XCTAssertEqual(FileOperationText.spokenDuration(61), "1 minute")
        XCTAssertEqual(FileOperationText.spokenDuration(150), "3 minutes")
    }

    func testRouteNamesWhichHalvesAreKnown() {
        let folder = URL(fileURLWithPath: "/tmp/a")
        XCTAssertEqual(FileOperationText.route(source: nil, destination: nil), nil)
        XCTAssertTrue(FileOperationText.route(source: folder, destination: nil)?.hasPrefix("From ") == true)
        XCTAssertTrue(FileOperationText.route(source: nil, destination: folder)?.hasPrefix("To ") == true)
    }
}
