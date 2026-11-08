import XCTest
@testable import OneRoot
@testable import OneRootLinux

/// Which Quick Actions are offered, by file extension (Linux asks no type
/// database), and the sheet model's reordering.
final class QuickActionCatalogLinuxTests: XCTestCase {
    private let catalog = QuickActionCatalog(services: OneRootApp.quickActionServices)

    private func node(_ name: String, directory: Bool = false) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/tmp/qa/\(name)"), name: name, isDirectory: directory, size: nil, modificationDate: nil, kind: nil)
    }

    private func actions(_ names: [String]) -> [QuickAction] {
        catalog.options(for: names.map { node($0) }).filter(\.isAvailable).map(\.action)
    }

    func testImages() {
        XCTAssertEqual(actions(["a.png", "b.jpg"]), [.resizeImages, .convertImages, .removeImageMetadata, .combineIntoPDF])
    }

    func testPlainTextMarkdownAndHTML() {
        XCTAssertEqual(actions(["a.txt"]), [.convertToPDF, .textToMarkdown])
        XCTAssertEqual(actions(["a.md"]), [.markdownToHTML])
        XCTAssertEqual(actions(["a.html"]), [.htmlToMarkdown])
    }

    func testOnePDFHasNothingToCombineAndTwoDo() {
        XCTAssertEqual(actions(["a.pdf"]), [])
        XCTAssertEqual(actions(["a.pdf", "b.pdf"]), [.combineIntoPDF])
    }

    func testWordDocumentsAreNotOfferedOnLinux() {
        XCTAssertEqual(catalog.kind(of: node("a.docx")), .other)
        XCTAssertEqual(catalog.kind(of: node("a.rtf")), .other)
    }

    func testSourceCodeAndFoldersAreLeftAlone() {
        XCTAssertEqual(catalog.kind(of: node("main.swift")), .other)
        XCTAssertEqual(catalog.kind(of: node("data.json")), .other)
        XCTAssertEqual(catalog.kind(of: node("photos.png", directory: true)), .other)
    }

    func testMixedSelectionsExplainWhy() {
        let options = catalog.options(for: [node("a.png"), node("b.txt")])
        let resize = options.first { $0.action == .resizeImages }
        XCTAssertEqual(resize?.isAvailable, false)
        XCTAssertNotNil(resize?.unavailableReason)
    }

    @MainActor
    func testSheetModelReordersTheCombineList() {
        let urls = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/tmp/qa/\($0).pdf") }
        let model = QuickActionSheetModel(action: .combineIntoPDF, urls: urls)
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(model.urls.map(\.lastPathComponent), ["b.pdf", "c.pdf", "a.pdf", "d.pdf"])
        model.move(fromOffsets: IndexSet([2, 3]), toOffset: 0)
        XCTAssertEqual(model.urls.map(\.lastPathComponent), ["a.pdf", "d.pdf", "b.pdf", "c.pdf"])
        model.move(at: 0, by: 1)
        XCTAssertEqual(model.urls.map(\.lastPathComponent), ["d.pdf", "a.pdf", "b.pdf", "c.pdf"])
        model.move(at: 3, by: 1)
        XCTAssertEqual(model.urls.map(\.lastPathComponent), ["d.pdf", "a.pdf", "b.pdf", "c.pdf"])
    }
}
