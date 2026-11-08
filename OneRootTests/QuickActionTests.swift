import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OneRoot

/// Test images and PDFs, drawn in a temporary folder.
enum QuickActionFixtures {
    /// A `width`×`height` image of `type`, optionally with transparency,
    /// GPS and EXIF metadata, an EXIF orientation, or several frames.
    @discardableResult
    static func image(
        at url: URL,
        type: UTType = .jpeg,
        width: Int = 400,
        height: Int = 200,
        alpha: Bool = false,
        withMetadata: Bool = false,
        orientation: Int? = nil,
        frames: Int = 1
    ) throws -> URL {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        var properties: [CFString: Any] = [:]
        if withMetadata {
            properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 46.8, kCGImagePropertyGPSLatitudeRef: "N"]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "secret", kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"]
        }
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        for _ in 0..<frames {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    @discardableResult
    static func pdf(at url: URL, pages: Int) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    static func properties(of url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
}

final class QuickActionCatalogTests: XCTestCase {
    private let catalog = QuickActionCatalog(readableImageTypes: [UTType.jpeg.identifier, UTType.png.identifier])

    private func node(_ name: String, directory: Bool = false) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: directory, size: nil, modificationDate: nil, kind: nil)
    }

    func testImagesGetEveryImageActionAndCombine() {
        let options = catalog.options(for: [node("a.jpg"), node("b.PNG")])
        XCTAssertEqual(options.map(\.action), [.resizeImages, .convertImages, .removeImageMetadata, .combineIntoPDF])
        XCTAssertTrue(options.allSatisfy(\.isAvailable))
    }

    func testMixedSelectionDisablesWithAReason() {
        let options = catalog.options(for: [node("a.jpg"), node("notes.txt")])
        XCTAssertEqual(options.map(\.action), [.resizeImages, .convertImages, .removeImageMetadata, .convertToPDF, .combineIntoPDF, .textToMarkdown])
        // An image and a text file can be combined into one PDF; nothing
        // else here applies to both.
        let available = options.filter(\.isAvailable).map(\.action)
        XCTAssertEqual(available, [.combineIntoPDF])
        XCTAssertTrue(options.filter { !$0.isAvailable }.allSatisfy { $0.unavailableReason != nil })
    }

    func testImagesAndPDFsCanBeCombinedButNotResized() {
        let options = catalog.options(for: [node("a.jpg"), node("b.pdf")])
        XCTAssertEqual(options.first { $0.action == .combineIntoPDF }?.isAvailable, true)
        XCTAssertEqual(options.first { $0.action == .resizeImages }?.isAvailable, false)
    }

    func testOnePDFOffersNothingButTwoCombine() {
        XCTAssertEqual(catalog.options(for: [node("a.pdf")]), [])
        XCTAssertEqual(catalog.options(for: [node("a.pdf"), node("b.pdf")]).map(\.action), [.combineIntoPDF])
    }

    func testFoldersArchivesAndUnreadableImageTypesOfferNothing() {
        XCTAssertEqual(catalog.options(for: [node("Photos.jpg", directory: true)]), [])
        XCTAssertEqual(catalog.options(for: [node("archive.zip")]), [])
        // An image type ImageIO (here, the injected list) can't read.
        XCTAssertEqual(catalog.options(for: [node("drawing.svg")]), [])
        XCTAssertEqual(catalog.options(for: []), [])
    }
}

final class QuickActionPlannerTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/plan", isDirectory: true)
    private var existing: Set<String> = []

    private var planner: QuickActionPlanner {
        let existing = existing
        return QuickActionPlanner(exists: { existing.contains($0.lastPathComponent) })
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    private func info(_ width: Int, _ height: Int, format: ImageFormat? = .jpeg, frames: Int = 1, alpha: Bool = false, metadata: [String] = ["EXIF"]) -> ImageInfo {
        ImageInfo(width: width, height: height, frameCount: frames, hasAlpha: alpha, format: format, metadataKinds: metadata)
    }

    func testResizeTargetNeverEnlarges() {
        XCTAssertEqual(ImageResizeTarget.longestSide(1000).size(width: 4000, height: 3000)?.width, 1000)
        XCTAssertEqual(ImageResizeTarget.longestSide(1000).size(width: 4000, height: 3000)?.height, 750)
        XCTAssertEqual(ImageResizeTarget.percent(50).size(width: 101, height: 51)?.width, 51)
        XCTAssertNil(ImageResizeTarget.longestSide(5000).size(width: 4000, height: 3000))
        XCTAssertNil(ImageResizeTarget.percent(100).size(width: 4000, height: 3000))
    }

    func testResizeNamesSkipsAndWarns() {
        let a = url("a.jpg"), b = url("b.png"), c = url("c.jpg")
        let plan = planner.plan(.resize(.longestSide(1000), quality: 0.8), sources: [a, b, c], imageInfo: [
            a: info(4000, 3000), b: info(800, 600, format: .png),
        ])
        XCTAssertEqual(plan.items[0].output, url("a (resized).jpg"))
        XCTAssertEqual(plan.items[0].detail, "4000 \u{00D7} 3000 \u{2192} 1000 \u{00D7} 750")
        XCTAssertTrue(plan.items[1].isSkipped) // already small
        XCTAssertTrue(plan.items[2].isSkipped) // unreadable
        XCTAssertFalse(plan.warnings.isEmpty)
        XCTAssertFalse(plan.isEmpty)
    }

    func testOutputsAvoidExistingFilesAndEachOther() {
        existing = ["a.png"]
        let a = url("a.jpg"), a2 = url("a.gif")
        let plan = planner.plan(.convert(to: .png, quality: 1), sources: [a, a2], imageInfo: [a: info(10, 10), a2: info(10, 10, format: nil)])
        XCTAssertEqual(plan.items.map(\.output), [url("a (2).png"), url("a (3).png")])
    }

    func testConvertSkipsSameFormatAndNotesFramesAndTransparency() {
        let gif = url("anim.gif"), png = url("clear.png"), jpg = url("same.jpg")
        let plan = planner.plan(.convert(to: .jpeg, quality: 0.8), sources: [gif, png, jpg], imageInfo: [
            gif: info(10, 10, format: nil, frames: 5), png: info(10, 10, format: .png, alpha: true), jpg: info(10, 10),
        ])
        XCTAssertEqual(plan.items[0].note, "First frame only")
        XCTAssertEqual(plan.items[1].output, url("clear.jpg"))
        XCTAssertTrue(plan.items[2].isSkipped)
        XCTAssertEqual(plan.warnings.count, 2) // lossy, transparency
    }

    func testRemoveMetadataSkipsImagesWithout() {
        let a = url("a.jpg"), b = url("b.png")
        let plan = planner.plan(.removeMetadata, sources: [a, b], imageInfo: [a: info(1, 1, metadata: ["Location", "EXIF"]), b: info(1, 1, metadata: [])])
        XCTAssertEqual(plan.items[0].output, url("a (no metadata).jpg"))
        XCTAssertEqual(plan.items[0].detail, "Location, EXIF")
        XCTAssertTrue(plan.items[1].isSkipped)
    }

    func testCombineNamesTheOutputAndSkipsUnreadable() {
        existing = ["Report.pdf"]
        let a = url("a.pdf"), b = url("b.jpg"), locked = url("locked.pdf")
        let plan = planner.plan(.combine(name: "Report"), sources: [a, b, locked], pageCounts: [a: 3, b: 1])
        XCTAssertEqual(plan.combinedOutput, url("Report (2).pdf"))
        XCTAssertEqual(plan.items.map(\.detail), ["3 pages", "1 page", ""])
        XCTAssertTrue(plan.items[2].isSkipped)
        XCTAssertFalse(plan.isEmpty)
    }

    func testCombineNeedsAUsableName() {
        let a = url("a.pdf")
        XCTAssertNil(planner.plan(.combine(name: ""), sources: [a], pageCounts: [a: 1]).combinedOutput)
        XCTAssertTrue(planner.plan(.combine(name: ""), sources: [a], pageCounts: [a: 1]).isEmpty)
        XCTAssertEqual(QuickActionPlanner.fileName(from: " Notes.PDF "), "Notes")
        XCTAssertNil(QuickActionPlanner.fileName(from: "a/b"))
        XCTAssertNil(QuickActionPlanner.fileName(from: ".hidden"))
    }
}

final class ImageTransformServiceTests: XCTestCase {
    private let service = ImageTransformService()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    func testInfoReadsSizeFormatAndMetadata() throws {
        let photo = try QuickActionFixtures.image(at: url("p.jpg"), width: 400, height: 200, withMetadata: true, orientation: 6)
        let info = try service.info(for: photo)
        // Orientation 6 is a quarter turn, so it's seen as 200 × 400.
        XCTAssertEqual(info.width, 200)
        XCTAssertEqual(info.height, 400)
        XCTAssertEqual(info.format, .jpeg)
        XCTAssertTrue(info.metadataKinds.contains("Location"))
        XCTAssertThrowsError(try service.info(for: url("missing.jpg")))
    }

    func testResizeWritesASmallerCopyAndLeavesTheOriginal() throws {
        let photo = try QuickActionFixtures.image(at: url("p.jpg"), width: 400, height: 200)
        let original = try Data(contentsOf: photo)
        let written = try service.resize(photo, to: .longestSide(100), quality: 0.8, output: url("p (resized).jpg"))
        let properties = try QuickActionFixtures.properties(of: written)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 100)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 50)
        XCTAssertEqual(try Data(contentsOf: photo), original)
    }

    func testResizeKeepsEveryFrame() throws {
        let gif = try QuickActionFixtures.image(at: url("a.gif"), type: .gif, frames: 3)
        let written = try service.resize(gif, to: .percent(50), quality: 1, output: url("a (resized).gif"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(written as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
    }

    func testConvertChangesFormatAndFlattensTransparencyForJPEG() throws {
        let png = try QuickActionFixtures.image(at: url("a.png"), type: .png, alpha: true)
        let written = try service.convert(png, to: .jpeg, quality: 0.9, output: url("a.jpg"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(written as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(try QuickActionFixtures.properties(of: written)[kCGImagePropertyHasAlpha] as? Bool ?? false, false)
    }

    func testNeverReplacesAnExistingFile() throws {
        let photo = try QuickActionFixtures.image(at: url("a.jpg"))
        try Data("keep me".utf8).write(to: url("a.png"))
        let written = try service.convert(photo, to: .png, quality: 1, output: url("a.png"))
        XCTAssertEqual(written.lastPathComponent, "a (2).png")
        XCTAssertEqual(try String(contentsOf: url("a.png"), encoding: .utf8), "keep me")
    }

    func testRemoveMetadataStripsGPSAndEXIFButKeepsOrientation() throws {
        let photo = try QuickActionFixtures.image(at: url("p.jpg"), withMetadata: true, orientation: 6)
        XCTAssertNotNil(try QuickActionFixtures.properties(of: photo)[kCGImagePropertyGPSDictionary])
        let written = try service.removeMetadata(photo, output: url("p (no metadata).jpg"))
        let properties = try QuickActionFixtures.properties(of: written)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifUserComment])
        XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertEqual(try service.info(for: written).metadataKinds, [])
    }

    func testRemoveMetadataFromJPEGIsLossless() throws {
        let photo = try QuickActionFixtures.image(at: url("p.jpg"), withMetadata: true, orientation: 3)
        let written = try service.removeMetadata(photo, output: url("p (no metadata).jpg"))
        XCTAssertEqual(try pixels(of: written), try pixels(of: photo))
    }

    private func pixels(of url: URL) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    func testRemoveMetadataWorksForPNG() throws {
        let png = try QuickActionFixtures.image(at: url("a.png"), type: .png, withMetadata: true)
        let written = try service.removeMetadata(png, output: url("a (no metadata).png"))
        XCTAssertEqual(try service.info(for: png).metadataKinds, ["Location", "EXIF"])
        XCTAssertEqual(try service.info(for: written).metadataKinds, [])
    }

    func testPlainImagesHaveNoMetadataToRemove() throws {
        let plain = try QuickActionFixtures.image(at: url("plain.jpg"))
        XCTAssertEqual(try service.info(for: plain).metadataKinds, [])
    }

    func testFailedWriteLeavesNothingBehind() throws {
        XCTAssertThrowsError(try service.resize(url("missing.jpg"), to: .percent(50), quality: 1, output: url("out.jpg")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }
}

final class PDFCombineServiceTests: XCTestCase {
    private let service = PDFCombineService()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    func testCombinesPDFsAndImagesInOrder() throws {
        let a = try QuickActionFixtures.pdf(at: url("a.pdf"), pages: 2)
        let image = try QuickActionFixtures.image(at: url("b.png"), type: .png, width: 144, height: 72)
        let c = try QuickActionFixtures.pdf(at: url("c.pdf"), pages: 1)
        XCTAssertEqual(service.pageCount(of: a), 2)
        XCTAssertEqual(service.pageCount(of: image), 1)

        let written = try service.combine([a, image, c], output: url("Combined.pdf"))
        let document = try XCTUnwrap(PDFDocument(url: written))
        XCTAssertEqual(document.pageCount, 4)
        // The image page, third, is its own size (72 dpi: 144 × 72 points).
        let imagePage = try XCTUnwrap(document.page(at: 2))
        XCTAssertEqual(imagePage.bounds(for: .mediaBox).width, 144, accuracy: 0.5)
        XCTAssertEqual(imagePage.bounds(for: .mediaBox).height, 72, accuracy: 0.5)
    }

    func testUnreadableSourceFailsWithoutWriting() throws {
        try Data("not a pdf".utf8).write(to: url("bad.pdf"))
        XCTAssertNil(service.pageCount(of: url("bad.pdf")))
        XCTAssertThrowsError(try service.combine([url("bad.pdf")], output: url("Combined.pdf")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url("Combined.pdf").path))
    }
}

@MainActor
final class QuickActionRunnerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testRunsThePlanRecordsTheOperationAndUndoRemovesOutputs() async throws {
        let a = try QuickActionFixtures.image(at: folder.appendingPathComponent("a.jpg"))
        let b = try QuickActionFixtures.image(at: folder.appendingPathComponent("b.jpg"))
        let progress = FileOperationProgressCenter(defaults: .isolatedForTests())
        let undo = FileUndoCenter(presentError: { _ in })
        let runner = QuickActionRunner(progressCenter: progress, undoCenter: undo)
        let service = ImageTransformService()
        let request = QuickActionRequest.resize(.percent(50), quality: 0.8)
        let plan = QuickActionPlanner().plan(request, sources: [a, b], imageInfo: [a: try service.info(for: a), b: try service.info(for: b)])

        let result = await runner.run(request, plan: plan)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.created.map(\.lastPathComponent), ["a (resized).jpg", "b (resized).jpg"])
        XCTAssertTrue(progress.operations.isEmpty)
        XCTAssertEqual(progress.recent.first?.outcome, .succeeded)
        XCTAssertEqual(progress.recent.first?.title, "Resizing 2 items")
        XCTAssertEqual(undo.undoActionName, "Resize 2 Images")

        undo.undo()
        await undo.pendingRevert?.value
        for url in result.created {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testAFailureKeepsWhatWasMadeAndRecordsIt() async throws {
        let a = try QuickActionFixtures.image(at: folder.appendingPathComponent("a.jpg"))
        let gone = folder.appendingPathComponent("gone.jpg")
        let progress = FileOperationProgressCenter(defaults: .isolatedForTests())
        let undo = FileUndoCenter(presentError: { _ in })
        let runner = QuickActionRunner(progressCenter: progress, undoCenter: undo)
        let info = try ImageTransformService().info(for: a)
        // Planned while "gone.jpg" was there, deleted before running.
        let request = QuickActionRequest.removeMetadata
        let plan = QuickActionPlanner().plan(request, sources: [a, gone], imageInfo: [
            a: ImageInfo(width: info.width, height: info.height, frameCount: 1, hasAlpha: false, format: .jpeg, metadataKinds: ["EXIF"]),
            gone: ImageInfo(width: 1, height: 1, frameCount: 1, hasAlpha: false, format: .jpeg, metadataKinds: ["EXIF"]),
        ])

        let result = await runner.run(request, plan: plan)

        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.created.count, 1)
        XCTAssertTrue(progress.recent.first?.outcome.isFailure ?? false)
        XCTAssertEqual(progress.recent.first?.finishedItems, 1)
        XCTAssertTrue(undo.canUndo)
    }
}

final class QuickActionTextCatalogTests: XCTestCase {
    private let catalog = QuickActionCatalog(readableImageTypes: [])

    private func node(_ name: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: false, size: nil, modificationDate: nil, kind: nil)
    }

    func testTextKinds() {
        XCTAssertEqual(catalog.options(for: [node("a.txt"), node("b.log")]).map(\.action), [.convertToPDF, .combineIntoPDF, .textToMarkdown])
        XCTAssertEqual(catalog.options(for: [node("README.md"), node("x.markdown")]).map(\.action), [.markdownToHTML])
        XCTAssertEqual(catalog.options(for: [node("page.html"), node("old.htm")]).map(\.action), [.htmlToMarkdown])
    }

    func testCodeAndDataFilesAreNotPlainText() {
        for name in ["main.swift", "data.json", "table.csv", "feed.xml", "script.py"] {
            XCTAssertEqual(catalog.options(for: [node(name)]), [], name)
        }
    }

    func testMixedTextSelectionExplains() {
        let options = catalog.options(for: [node("a.txt"), node("b.md")])
        XCTAssertEqual(options.map(\.action), [.convertToPDF, .combineIntoPDF, .textToMarkdown, .markdownToHTML])
        XCTAssertTrue(options.allSatisfy { !$0.isAvailable })
    }

    func testPlannerNamesTextOutputs() {
        let a = URL(fileURLWithPath: "/tmp/t/a.txt"), b = URL(fileURLWithPath: "/tmp/t/b.txt")
        let planner = QuickActionPlanner(exists: { _ in false })
        let plan = planner.plan(.textToMarkdown(keepLineBreaks: true, escapeSymbols: false), sources: [a, b], textInfo: [a: TextInfo(lineCount: 1)])
        XCTAssertEqual(plan.items[0].output?.lastPathComponent, "a.md")
        XCTAssertEqual(plan.items[0].detail, "1 line")
        XCTAssertTrue(plan.items[1].isSkipped)
        let html = planner.plan(.markdownToHTML(styled: true), sources: [a], textInfo: [a: TextInfo(lineCount: 2)])
        XCTAssertEqual(html.items[0].output?.lastPathComponent, "a.html")
    }
}
