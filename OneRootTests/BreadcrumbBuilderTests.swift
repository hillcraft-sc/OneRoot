import XCTest
@testable import OneRoot

final class BreadcrumbBuilderTests: XCTestCase {
    private func names(_ path: String) -> [String] {
        BreadcrumbBuilder.segments(for: URL(fileURLWithPath: path)) { $0.path == "/" ? "Macintosh HD" : $0.lastPathComponent }
            .map(\.name)
    }

    func testBootVolumePathStartsAtTheVolumeName() {
        XCTAssertEqual(names("/Users/eric/Documents"), ["Macintosh HD", "Users", "eric", "Documents"])
    }

    func testRootIsJustTheVolume() {
        XCTAssertEqual(names("/"), ["Macintosh HD"])
    }

    func testExternalVolumeStartsAtThatVolume() {
        XCTAssertEqual(names("/Volumes/USB Stick/Photos/2026"), ["USB Stick", "Photos", "2026"])
    }

    func testVolumesFolderItselfStaysUnderTheBootVolume() {
        XCTAssertEqual(names("/Volumes"), ["Macintosh HD", "Volumes"])
    }

    func testEachSegmentPointsAtItsOwnFolder() {
        let segments = BreadcrumbBuilder.segments(for: URL(fileURLWithPath: "/Volumes/USB/Photos")) { $0.lastPathComponent }
        XCTAssertEqual(segments.map(\.url.path), ["/Volumes/USB", "/Volumes/USB/Photos"])
    }

    func testPathIsStandardizedFirst() {
        XCTAssertEqual(names("/Users/eric/../eric/./Documents/"), ["Macintosh HD", "Users", "eric", "Documents"])
    }
}
