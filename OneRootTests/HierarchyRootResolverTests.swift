import XCTest
@testable import OneRoot

final class HierarchyRootResolverTests: XCTestCase {
    private let bootVolume = HierarchyRoot(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", kind: .bootVolume)
    private let home = HierarchyRoot(url: URL(fileURLWithPath: "/Users/test"), name: "test", kind: .home)
    private let applications = HierarchyRoot(url: URL(fileURLWithPath: "/Applications"), name: "Applications", kind: .applications)
    private let trash = HierarchyRoot(url: URL(fileURLWithPath: "/Users/test/.Trash"), name: "Trash", kind: .trash)
    private let pinned = HierarchyRoot(url: URL(fileURLWithPath: "/Users/test/Projects/Phoenix"), name: "Phoenix", kind: .pinned)
    private let usb = HierarchyRoot(url: URL(fileURLWithPath: "/Volumes/USB"), name: "USB", kind: .volume)

    private var candidates: [HierarchyRoot] { [home, pinned, bootVolume, applications, usb, trash] }

    private func root(_ path: String, current: HierarchyRoot? = nil) -> HierarchyRoot {
        HierarchyRootResolver.root(for: URL(fileURLWithPath: path), current: current, candidates: candidates)
    }

    func testFolderInsideHomeIsRootedAtHome() {
        XCTAssertEqual(root("/Users/test/Documents/Notes"), home)
    }

    func testMostSpecificDestinationWins() {
        XCTAssertEqual(root("/Users/test/Projects/Phoenix/Design"), pinned)
        XCTAssertEqual(root("/Users/test/.Trash"), trash)
        XCTAssertEqual(root("/Applications/Utilities"), applications)
    }

    func testCurrentRootSticksWhileItStillContainsTheLocation() {
        // Opened from Home, then browsed into a folder that's also pinned:
        // the hierarchy shouldn't jump to the pinned root.
        XCTAssertEqual(root("/Users/test/Projects/Phoenix/Design", current: home), home)
    }

    func testLeavingTheCurrentRootPicksTheNearestDestination() {
        // Up from Home to /Users: Home no longer contains it.
        XCTAssertEqual(root("/Users", current: home), bootVolume)
        XCTAssertEqual(root("/Volumes/USB/Photos", current: home), usb)
    }

    func testARootThatStoppedBeingADestinationDoesNotStick() {
        let unpinned = HierarchyRoot(url: URL(fileURLWithPath: "/Users/test/Old"), name: "Old", kind: .pinned)

        XCTAssertEqual(root("/Users/test/Old/Sub", current: unpinned), home)
    }

    func testStickyRootPicksUpARefreshedName() {
        let staleName = HierarchyRoot(url: URL(fileURLWithPath: "/Volumes/USB"), name: "Untitled", kind: .volume)

        XCTAssertEqual(root("/Volumes/USB/Photos", current: staleName).name, "USB")
    }

    func testFallsBackToTheFilesystemRootWithNoMatchingDestination() {
        let result = HierarchyRootResolver.root(for: URL(fileURLWithPath: "/usr/local"), current: nil, candidates: [home])

        XCTAssertEqual(result, HierarchyRootResolver.fallbackRoot)
    }

    func testSiblingWithSharedPrefixIsNotInside() {
        // "/Users/testing" starts with "/Users/test" as a string, but isn't
        // inside it.
        XCTAssertEqual(root("/Users/testing"), bootVolume)
    }

    func testSymlinkedAndResolvedFormsMatch() {
        // /var is a symlink to /private/var on macOS — FSEvents and some
        // mount paths report one form, FileManager the other.
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL
        guard temp.path.hasPrefix("/var/") else { return }
        let privateForm = URL(fileURLWithPath: "/private" + temp.path)
        let root = HierarchyRoot(url: privateForm, name: "tmp", kind: .pinned)

        XCTAssertTrue(root.contains(temp.appendingPathComponent("child")))
        XCTAssertTrue(HierarchyRootResolver.sameLocation(privateForm, temp))
    }
}
