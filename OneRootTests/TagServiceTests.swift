import XCTest
@testable import OneRoot

final class TagServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testWritesAndReadsBackTags() throws {
        let file = tempDirectory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let service = TagService()

        try service.setTags(["Red", "Project"], on: file)
        XCTAssertEqual(try service.tags(of: file), ["Red", "Project"])

        try service.setTags([], on: file)
        XCTAssertEqual(try service.tags(of: file), [])
    }

    func testTagsAFolder() throws {
        let folder = tempDirectory.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TagService().setTags(["Blue"], on: folder)
        XCTAssertEqual(try TagService().tags(of: folder), ["Blue"])
    }

    func testWritingToAMissingFileThrows() {
        let missing = tempDirectory.appendingPathComponent("missing.txt")
        XCTAssertThrowsError(try TagService().setTags(["Red"], on: missing))
    }

    @MainActor
    func testTheInspectorShowsReloadedCopiesOfTheSameSelection() {
        func node(_ name: String, _ tags: [String]) -> FileNode {
            FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: false, size: nil, modificationDate: nil, kind: nil, tags: tags)
        }
        let shown = [node("a", []), node("b", [])]
        let reloaded = [node("a", ["Red"]), node("b", ["Red"])]
        XCTAssertEqual(InspectorView.displayed(shown: shown, current: reloaded).map(\.tags), [["Red"], ["Red"]])
        // A different selection isn't swapped in early.
        let other = [node("c", ["Blue"])]
        XCTAssertEqual(InspectorView.displayed(shown: shown, current: other).map(\.name), ["a", "b"])
    }

    func testUsageCountsEachTagOncePerItemInAnyCase() {
        let usage = TagService.usage(in: [["Red", "Work"], ["red"], ["Work", "work", "Blue"]])
        XCTAssertEqual(usage, [
            TagService.Usage(tag: "Red", count: 2),
            TagService.Usage(tag: "Work", count: 2),
            TagService.Usage(tag: "Blue", count: 1),
        ])
        XCTAssertEqual(TagService.usage(in: [[], []]), [])
    }

    func testAddingTrimsAndIgnoresDuplicatesInAnyCase() {
        XCTAssertEqual(TagService.adding("  Work ", to: ["Red"]), ["Red", "Work"])
        XCTAssertEqual(TagService.adding("red", to: ["Red"]), ["Red"])
        XCTAssertEqual(TagService.adding("   ", to: ["Red"]), ["Red"])
    }

    func testRemovingIgnoresCase() {
        XCTAssertEqual(TagService.removing("work", from: ["Red", "Work"]), ["Red"])
        XCTAssertEqual(TagService.removing("Green", from: ["Red"]), ["Red"])
    }

    func testSuggestionsListStandardTagsFirstThenFolderTagsWithoutRepeats() {
        let suggestions = TagService.suggestions(
            standard: ["Red", "Orange", "Blue"],
            inFolder: [["Work", "red"], ["Archive"], []],
            excluding: ["Orange"]
        )
        XCTAssertEqual(suggestions, ["Red", "Blue", "Archive", "Work"])
    }
}
