import XCTest
@testable import OneRoot

final class SearchResultExportServiceTests: XCTestCase {
    private let service = SearchResultExportService()

    private func makeMetadataResult(name: String = "notes.txt", size: Int64 = 1024) -> SearchResult {
        let node = FileNode(
            url: URL(fileURLWithPath: "/Users/eric/Documents/\(name)"),
            name: name,
            isDirectory: false,
            size: size,
            modificationDate: nil,
            kind: "Plain Text"
        )
        return SearchResult(node: node, contentMatch: nil)
    }

    private func makeContentResult(name: String = "notes.txt", snippet: String = "hello, world") -> SearchResult {
        let node = FileNode(
            url: URL(fileURLWithPath: "/Users/eric/Documents/\(name)"),
            name: name,
            isDirectory: false,
            size: 1024,
            modificationDate: nil,
            kind: "Plain Text"
        )
        return SearchResult(node: node, contentMatch: ContentMatch(lineNumber: 3, snippet: snippet))
    }

    func testCSVIncludesHeaderAndEscapesCommas() {
        let output = service.export([makeMetadataResult(name: "a, b.txt")], mode: .nameAndMetadata, format: .csv)

        let lines = output.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "Name,Size,Date Modified,Path")
        XCTAssertEqual(lines[1], "\"a, b.txt\",1 KB,,/Users/eric/Documents")
    }

    func testContentModeCSVHasLineAndMatchColumns() {
        let output = service.export([makeContentResult()], mode: .contents, format: .csv)

        let lines = output.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "Name,Line,Match,Path")
        XCTAssertEqual(lines[1], "notes.txt,3,\"hello, world\",/Users/eric/Documents")
    }

    func testMarkdownProducesATableWithHeaderSeparator() {
        let output = service.export([makeMetadataResult()], mode: .nameAndMetadata, format: .markdown)

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines[0], "| Name | Size | Date Modified | Path |")
        XCTAssertEqual(lines[1], "| --- | --- | --- | --- |")
        XCTAssertTrue(lines[2].contains("notes.txt"))
    }

    func testPlainTextIncludesEveryColumnLabel() {
        let output = service.export([makeMetadataResult()], mode: .nameAndMetadata, format: .plainText)

        XCTAssertTrue(output.contains("Name: notes.txt"))
        XCTAssertTrue(output.contains("Size: 1 KB"))
    }

    func testInteractiveHTMLEscapesResultContentAndIncludesEachRow() {
        let output = service.export([makeMetadataResult(name: "<script>.txt")], mode: .nameAndMetadata, format: .interactiveHTML)

        XCTAssertTrue(output.contains("<!DOCTYPE html>"))
        XCTAssertTrue(output.contains("&lt;script&gt;.txt"))
        XCTAssertFalse(output.contains("<script>.txt<")) // must not appear unescaped
    }

    func testEmptyResultsStillProduceAHeaderRow() {
        let csv = service.export([], mode: .nameAndMetadata, format: .csv)

        XCTAssertEqual(csv.trimmingCharacters(in: .whitespacesAndNewlines), "Name,Size,Date Modified,Path")
    }
}
