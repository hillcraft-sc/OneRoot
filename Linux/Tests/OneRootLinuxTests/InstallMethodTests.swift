import XCTest
@testable import OneRootLinux

/// Which installs check for updates (packages don't).
final class InstallMethodTests: XCTestCase {
    private func prefix(marker: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oneroot-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        if let marker {
            let dir = root.appendingPathComponent("share/oneroot")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try marker.write(to: dir.appendingPathComponent(InstallMethod.markerName), atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testMarkerMeansTarball() throws {
        let root = try prefix(marker: "tarball\n")
        XCTAssertEqual(InstallMethod.detect(executable: root.appendingPathComponent("bin/oneroot"), environment: [:]), .tarball)
    }

    func testNoMarkerOrAnotherMarkerMeansOther() throws {
        let none = try prefix(marker: nil)
        XCTAssertEqual(InstallMethod.detect(executable: none.appendingPathComponent("bin/oneroot"), environment: [:]), .other)
        let deb = try prefix(marker: "deb")
        XCTAssertEqual(InstallMethod.detect(executable: deb.appendingPathComponent("bin/oneroot"), environment: [:]), .other)
        XCTAssertFalse(InstallMethod.other.checksForUpdates)
    }

    func testEnvironmentOverride() throws {
        let root = try prefix(marker: nil)
        let exe = root.appendingPathComponent("bin/oneroot")
        XCTAssertEqual(InstallMethod.detect(executable: exe, environment: ["ONEROOT_INSTALL_METHOD": "tarball"]), .tarball)
        let tar = try prefix(marker: "tarball")
        XCTAssertEqual(InstallMethod.detect(executable: tar.appendingPathComponent("bin/oneroot"), environment: ["ONEROOT_INSTALL_METHOD": "deb"]), .other)
    }
}
