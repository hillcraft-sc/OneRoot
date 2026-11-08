import XCTest
@testable import OneRoot

/// The in-process clipboard (tests, and Linux until the app there supplies
/// the desktop's).
@MainActor
final class FileClipboardTests: XCTestCase {
    func testFilesKeepWhetherTheyWereCut() {
        let clipboard = MemoryClipboard()
        XCTAssertNil(clipboard.files())

        clipboard.write([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")], operation: .cut)

        XCTAssertEqual(clipboard.files()?.urls.map(\.path), ["/a", "/b"])
        XCTAssertEqual(clipboard.files()?.isCut, true)
        XCTAssertTrue(clipboard.hasFiles)
    }

    func testTextReplacesFilesAndEveryWriteCounts() {
        let clipboard = MemoryClipboard()
        clipboard.write([URL(fileURLWithPath: "/a")], operation: .copy)
        clipboard.write(text: "/a")

        XCTAssertNil(clipboard.files(), "text on the clipboard isn't files to paste")
        XCTAssertEqual(clipboard.string, "/a")
        clipboard.clear()
        XCTAssertNil(clipboard.string)
        XCTAssertEqual(clipboard.changeCount, 3)
    }

    func testTrackerForgetsOnceTheClipboardChanges() {
        let clipboard = MemoryClipboard()
        let tracker = ClipboardTracker(clipboard: clipboard)
        clipboard.write([URL(fileURLWithPath: "/a")], operation: .copy)
        tracker.record(count: 1, operation: .copy)

        tracker.refresh()
        XCTAssertEqual(tracker.pending, .init(count: 1, operation: .copy))

        clipboard.write(text: "something else")
        tracker.refresh()
        XCTAssertNil(tracker.pending)
    }
}
