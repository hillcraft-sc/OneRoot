import AppKit
import PDFKit
import XCTest
@testable import OneRoot

@MainActor
final class DocumentPDFTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A document with a bold heading and a body, written in `type`.
    private func document(_ name: String, _ type: NSAttributedString.DocumentType) throws -> URL {
        let text = NSMutableAttributedString(string: "Quarterly Report\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        text.append(NSAttributedString(string: "The body text of the report.", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func pdfText(_ url: URL) throws -> String {
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        return pdf.string ?? ""
    }

    func testWordRTFAndTextBecomePDFsWithTheirText() async throws {
        let docx = try document("report.docx", .officeOpenXML)
        let rtf = try document("report.rtf", .rtf)
        let txt = folder.appendingPathComponent("notes.txt")
        try "Plain notes, café.".write(to: txt, atomically: true, encoding: .utf8)

        for (source, expected) in [(docx, "Quarterly Report"), (rtf, "The body text"), (txt, "Plain notes, café.")] {
            let written = try await DocumentPDFRenderer.convert(source, output: source.deletingPathExtension().appendingPathExtension("pdf"))
            XCTAssertTrue(try pdfText(written).contains(expected), "\(source.lastPathComponent)")
        }
    }

    func testNeverReplacesAnExistingPDF() async throws {
        let rtf = try document("letter.rtf", .rtf)
        let existing = folder.appendingPathComponent("letter.pdf")
        try Data("keep".utf8).write(to: existing)

        let written = try await DocumentPDFRenderer.convert(rtf, output: existing)

        XCTAssertEqual(written.lastPathComponent, "letter (2).pdf")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep")
    }

    func testCatalogOffersConvertToPDFForDocumentsAndCombineForMixes() {
        let catalog = QuickActionCatalog(readableImageTypes: [])
        func node(_ name: String) -> FileNode {
            FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: false, size: nil, modificationDate: nil, kind: nil)
        }
        XCTAssertEqual(catalog.options(for: [node("a.docx")]).map(\.action), [.convertToPDF])
        let mixed = catalog.options(for: [node("a.docx"), node("b.pdf")])
        XCTAssertEqual(mixed.first { $0.action == .combineIntoPDF }?.isAvailable, true)
        XCTAssertEqual(mixed.first { $0.action == .convertToPDF }?.isAvailable, false)
        XCTAssertEqual(catalog.options(for: [node("a.txt")]).map(\.action), [.convertToPDF, .textToMarkdown])
    }

    func testCombinePutsADocumentsPagesInOrder() async throws {
        let rtf = try document("cover.rtf", .rtf)
        let pdfURL = folder.appendingPathComponent("rest.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(pdfURL as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()

        let request = QuickActionRequest.combine(name: "Bundle")
        let plan = QuickActionPlanner().plan(request, sources: [rtf, pdfURL], pageCounts: [pdfURL: 1], documents: [rtf])
        let undo = FileUndoCenter(presentError: { _ in })
        let result = await QuickActionRunner(progressCenter: FileOperationProgressCenter(defaults: .isolatedForTests()), undoCenter: undo).run(request, plan: plan)

        XCTAssertNil(result.error)
        let combined = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(result.created.first)))
        XCTAssertEqual(combined.pageCount, 2)
        XCTAssertTrue(combined.page(at: 0)?.string?.contains("Quarterly Report") ?? false, "the document's page comes first")
    }
}
