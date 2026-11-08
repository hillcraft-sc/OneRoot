import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// Combines PDFs and images into one PDF, in the order given — PDFKit for
/// the PDFs (so their links and annotations come along), Core Graphics to
/// make a page from each image. Uses no AppKit API. Synchronous — call off
/// the main actor; checks for cancellation between items.
struct PDFCombineService: PDFCombining {
    /// How many pages `url` will add: its page count for a PDF, 1 for an
    /// image, `nil` when it can't be read.
    func pageCount(of url: URL) -> Int? {
        if let document = PDFDocument(url: url) {
            return document.isLocked ? nil : document.pageCount
        }
        // A source is made for any file; it's an image only if it has one.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        return 1
    }

    /// Writes `sources` as one PDF to `output`; `progress` gets the index
    /// of each source as it's started. Returns where it was written.
    @discardableResult
    func combine(_ sources: [URL], output: URL, progress: (Int) -> Void = { _ in }) throws -> URL {
        let combined = PDFDocument()
        for (index, url) in sources.enumerated() {
            try Task.checkCancellation()
            progress(index)
            let pages = try pages(from: url)
            for page in pages {
                combined.insert(page, at: combined.pageCount)
            }
        }
        try Task.checkCancellation()
        return try SafeFileWriter.write(to: output) { temporary in
            guard combined.write(to: temporary) else { throw PDFCombineError.failed(output.lastPathComponent) }
        }
    }

    private func pages(from url: URL) throws -> [PDFPage] {
        let document: PDFDocument
        if let pdf = PDFDocument(url: url) {
            guard !pdf.isLocked else { throw PDFCombineError.locked(url.lastPathComponent) }
            document = pdf
        } else {
            document = try Self.singlePageDocument(fromImageAt: url)
        }
        // A page can only belong to one document, so take copies.
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.copy() as? PDFPage }
    }

    /// One page the size of the image as it's meant to be seen: turned the
    /// right way up, at its own resolution (72 dpi when it doesn't say).
    private static func singlePageDocument(fromImageAt url: URL) throws -> PDFDocument {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw PDFCombineError.unreadable(name) }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PDFCombineError.unreadable(name)
        }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        var mediaBox = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw PDFCombineError.failed(name) }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: data as Data) else { throw PDFCombineError.failed(name) }
        return document
    }
}
