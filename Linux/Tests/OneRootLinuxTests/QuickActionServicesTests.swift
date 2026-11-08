import CAdwaita
import XCTest
@testable import OneRoot
@testable import OneRootLinux

/// The Linux Quick Action services against real files in a temp folder:
/// GdkPixbuf, qpdf and Cairo/Pango do the work, so these run where they are.
final class QuickActionServicesTests: XCTestCase {
    private var folder: URL!
    private let images = LinuxImageTransformService()
    private let pdfs = LinuxPDFCombineService()
    private let documents = LinuxDocumentPDFConverter()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("oneroot-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A solid-colour image written by GdkPixbuf, as `type` ("png", "jpeg").
    private func makeImage(_ name: String, width: Int32, height: Int32, alpha: Bool = false, type: String = "png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        guard let pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, alpha ? 1 : 0, 8, width, height) else { throw XCTSkip("no pixbuf") }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        gdk_pixbuf_fill(pixbuf, 0x3366CCFF)
        var error: UnsafeMutablePointer<GError>?
        XCTAssertNotEqual(gdk_pixbuf_savev(pixbuf, url.path, type, nil, nil, &error), 0)
        return url
    }

    // MARK: Images

    func testInfoReadsSizeFormatAndAlpha() throws {
        let png = try makeImage("a.png", width: 40, height: 20, alpha: true)
        let info = try images.info(for: png)
        XCTAssertEqual(info.width, 40)
        XCTAssertEqual(info.height, 20)
        XCTAssertEqual(info.format, .png)
        XCTAssertTrue(info.hasAlpha)
        XCTAssertTrue(info.metadataKinds.isEmpty)
    }

    func testInfoOnANonImageThrows() throws {
        let text = folder.appendingPathComponent("a.png")
        try "not an image".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try images.info(for: text))
    }

    func testResizeWritesASmallerCopyAndLeavesTheOriginal() throws {
        let source = try makeImage("big.png", width: 200, height: 100)
        let output = folder.appendingPathComponent("big (resized).png")
        let written = try images.resize(source, to: .longestSide(50), quality: 0.8, output: output)
        let info = try images.info(for: written)
        XCTAssertEqual(info.width, 50)
        XCTAssertEqual(info.height, 25)
        XCTAssertEqual(try images.info(for: source).width, 200)
    }

    func testConvertPNGToJPEGFlattensTransparencyAndNeverOverwrites() throws {
        let source = try makeImage("t.png", width: 30, height: 30, alpha: true)
        let existing = folder.appendingPathComponent("t.jpg")
        try Data("keep me".utf8).write(to: existing)
        let written = try images.convert(source, to: .jpeg, quality: 0.9, output: existing)
        XCTAssertNotEqual(written, existing)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep me")
        XCTAssertEqual(try images.info(for: written).format, .jpeg)
    }

    func testWritableFormatsIncludeJPEGAndPNG() {
        XCTAssertTrue(images.writableFormats.contains(.jpeg))
        XCTAssertTrue(images.writableFormats.contains(.png))
        XCTAssertFalse(images.writableFormats.contains(.heic))
    }

    func testRemoveMetadataFromAPNGWithTextChunksIsLossless() throws {
        let base = try Data(contentsOf: makeImage("m.png", width: 8, height: 8))
        // Insert a tEXt chunk after IHDR (8 signature + 25 IHDR bytes).
        let key = Data("Author\0Someone".utf8)
        let chunk = Data([0, 0, 0, UInt8(key.count)]) + Data("tEXt".utf8) + key + Data([0, 0, 0, 0])
        var tagged = base
        tagged.insert(contentsOf: chunk, at: 33)
        let source = folder.appendingPathComponent("tagged.png")
        try tagged.write(to: source)
        XCTAssertEqual(ImageMetadata.inspect(tagged).kinds, [])  // plain text isn't personal metadata by itself
        let stripped = try XCTUnwrap(ImageMetadata.strippedPNG(tagged))
        XCTAssertEqual(stripped, base)
    }

    // MARK: PDF

    func testCombineTwoImagesAndAPDF() throws {
        let one = try makeImage("one.png", width: 100, height: 50)
        let two = try makeImage("two.jpg", width: 60, height: 60, type: "jpeg")
        // A PDF with two pages from text.
        let textFile = folder.appendingPathComponent("long.txt")
        try (0..<200).map { "line \($0)" }.joined(separator: "\n").write(to: textFile, atomically: true, encoding: .utf8)
        let textPDF = folder.appendingPathComponent("long.pdf")
        let expectation = expectation(description: "converted")
        Task { @MainActor in
            _ = try await documents.convert(textFile, output: textPDF)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30)
        let textPages = try XCTUnwrap(pdfs.pageCount(of: textPDF))
        XCTAssertGreaterThanOrEqual(textPages, 2)

        XCTAssertEqual(pdfs.pageCount(of: one), 1)
        var started: [Int] = []
        let output = folder.appendingPathComponent("all.pdf")
        let written = try pdfs.combine([one, textPDF, two], output: output) { started.append($0) }
        XCTAssertEqual(started, [0, 1, 2])
        XCTAssertEqual(pdfs.pageCount(of: written), 2 + textPages)
    }

    func testPageCountOfUnreadableFileIsNil() throws {
        let junk = folder.appendingPathComponent("junk.pdf")
        try Data("%PDF-1.4 broken".utf8).write(to: junk)
        XCTAssertNil(pdfs.pageCount(of: junk))
        let text = folder.appendingPathComponent("a.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertNil(pdfs.pageCount(of: text))
    }

    func testCombineRefusesAnUnreadablePDF() throws {
        let junk = folder.appendingPathComponent("junk.pdf")
        try Data("%PDF-1.4 broken".utf8).write(to: junk)
        XCTAssertThrowsError(try pdfs.combine([junk], output: folder.appendingPathComponent("o.pdf"), progress: { _ in }))
    }

    // MARK: Text to PDF

    func testDecodeRejectsBinaryAndAcceptsLatin1() throws {
        XCTAssertThrowsError(try LinuxDocumentPDFConverter.decode(Data([0x41, 0x00, 0x42]), name: "x"))
        XCTAssertEqual(try LinuxDocumentPDFConverter.decode(Data([0x63, 0x61, 0x66, 0xE9]), name: "x"), "caf\u{E9}")
    }
}
