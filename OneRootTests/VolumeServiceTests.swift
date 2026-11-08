import XCTest
@testable import OneRoot

final class VolumeServiceTests: XCTestCase {
    func testCurrentVolumesReturnsAtLeastTheBootVolume() {
        let volumes = VolumeService.currentVolumes()

        XCTAssertFalse(volumes.isEmpty, "expected at least the boot volume to be mounted")
    }

    func testVolumeMetadataIsPopulated() {
        let volumes = VolumeService.currentVolumes()

        let withCapacity = volumes.first { $0.totalCapacity != nil }
        XCTAssertNotNil(withCapacity, "expected at least one volume with capacity info")
    }

    func testVolumesAreSortedByName() {
        let names = VolumeService.currentVolumes().map(\.name)

        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
