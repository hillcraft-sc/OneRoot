import XCTest
@testable import OneRoot

final class FileWatcherTests: XCTestCase {
    func testWatcherFiresOnExternalChange() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let watcher = Platform.makeFileWatcher()
        let firedExpectation = expectation(description: "watcher fired after an external change")
        watcher.onChange = { firedExpectation.fulfill() }
        watcher.watch([tempDirectory])

        // Give the FSEvents stream a moment to actually start before making
        // a change, so the create isn't racing stream setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? "x".write(to: tempDirectory.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        }

        wait(for: [firedExpectation], timeout: 5)
        watcher.stop()
    }

    func testStopPreventsFurtherEvents() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let watcher = Platform.makeFileWatcher()
        var fireCount = 0
        watcher.onChange = { fireCount += 1 }
        watcher.watch([tempDirectory])
        watcher.stop()

        try? "x".write(to: tempDirectory.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let noFireExpectation = expectation(description: "no fire expected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { noFireExpectation.fulfill() }
        wait(for: [noFireExpectation], timeout: 2)

        XCTAssertEqual(fireCount, 0)
    }

    func testDrainChangedPathsReportsWhatActuallyChanged() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let newFile = tempDirectory.appendingPathComponent("new.txt")

        // FSEvents reports paths resolved through symlinks (e.g. `/private/
        // var/...`), while `newFile.path` is the unresolved `/var/...` form
        // — compare resolved forms rather than raw strings.
        let expectedPath = newFile.resolvingSymlinksInPath().path
        var seenPaths: Set<String> = []

        let watcher = Platform.makeFileWatcher()
        let sawNewFile = expectation(description: "watcher reported new.txt")
        // FSEvents can split one change across several deliveries (and a
        // busy machine makes that likelier), so keep draining until the
        // file shows up rather than assuming the first firing has it.
        watcher.onChange = {
            let resolved = watcher.drainChangedPaths().map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            seenPaths.formUnion(resolved)
            if seenPaths.contains(expectedPath) { sawNewFile.fulfill() }
        }
        sawNewFile.assertForOverFulfill = false
        watcher.watch([tempDirectory])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Not `atomically: true`: that writes a temporary file and
            // renames it, which FSEvents may report in separate batches.
            try? "x".write(to: newFile, atomically: false, encoding: .utf8)
        }

        wait(for: [sawNewFile], timeout: 5)
        XCTAssertTrue(seenPaths.contains(expectedPath))
        XCTAssertTrue(watcher.drainChangedPaths().isEmpty, "should clear on read")
        watcher.stop()
    }

    func testSeesChangesInsideAFolderCreatedAfterWatchingStarted() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let newFolder = tempDirectory.appendingPathComponent("later", isDirectory: true)
        let deepFile = newFolder.appendingPathComponent("deep.txt")
        let expectedPath = deepFile.resolvingSymlinksInPath().path

        let watcher = Platform.makeFileWatcher()
        let sawDeepFile = expectation(description: "watcher reported a file in the new folder")
        sawDeepFile.assertForOverFulfill = false
        var seen: Set<String> = []
        watcher.onChange = {
            seen.formUnion(watcher.drainChangedPaths().map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
            if seen.contains(expectedPath) { sawDeepFile.fulfill() }
        }
        watcher.watch([tempDirectory])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
            // Give the watcher a moment to pick up the new folder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? "x".write(to: deepFile, atomically: false, encoding: .utf8)
            }
        }

        wait(for: [sawDeepFile], timeout: 5)
        watcher.stop()
    }
}
