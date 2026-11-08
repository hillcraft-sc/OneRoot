import CAdwaita
import CPangoCairoPDF
import Foundation
@testable import OneRoot

/// Plain-text files as PDF on Linux: laid out with Pango in a monospaced
/// font on pages of the locale's paper size (A4 or Letter), ¾-inch margins,
/// written through Cairo's PDF surface. Word, RTF and OpenDocument are not
/// read on Linux (no text system to ask), so `documentExtensions` is empty.
/// The layout runs off the main thread: Pango and Cairo objects are made
/// and used inside one task.
struct LinuxDocumentPDFConverter: DocumentPDFConverting {
    var documentExtensions: Set<String> { [] }

    /// Text files over this are logs or data, not documents.
    static let maximumSize = 10_000_000

    @MainActor
    func convert(_ url: URL, output: URL) async throws -> URL {
        let text = try await Self.read(url)
        return try await Task.detached(priority: .userInitiated) {
            try SafeFileWriter.write(to: output) { temporary in
                try Self.render(text, to: temporary, name: url.lastPathComponent)
            }
        }.value
    }

    @MainActor
    func pdfData(for url: URL) async throws -> Data {
        let text = try await Self.read(url)
        return try await Task.detached(priority: .userInitiated) {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: scratch) }
            try Self.render(text, to: scratch, name: url.lastPathComponent)
            return try Data(contentsOf: scratch)
        }.value
    }

    // MARK: Reading

    private static func read(_ url: URL) async throws -> String {
        let name = url.lastPathComponent
        return try await Task.detached(priority: .userInitiated) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maximumSize else { throw DocumentPDFError.failed(name) }
            guard let data = try? Data(contentsOf: url) else { throw DocumentPDFError.unreadable(name) }
            return try decode(data, name: name)
        }.value
    }

    /// UTF-8 (or a BOM'd UTF-16), then Windows-1252; not binary.
    static func decode(_ data: Data, name: String) throws -> String {
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252] {
            if encoding == .utf16, !(data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])) { continue }
            if var text = String(data: data, encoding: encoding) {
                if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
                if text.contains("\u{0}") { break }
                return text
            }
        }
        throw DocumentPDFError.unreadable(name)
    }

    // MARK: Layout

    /// The locale's paper, in points (A4 where GTK has no opinion).
    private static func pageSize() -> (width: Double, height: Double) {
        if let name = gtk_paper_size_get_default(), let paper = gtk_paper_size_new(name) {
            defer { gtk_paper_size_free(paper) }
            let width = gtk_paper_size_get_width(paper, GTK_UNIT_POINTS)
            let height = gtk_paper_size_get_height(paper, GTK_UNIT_POINTS)
            if width > 100, height > 100 { return (width, height) }
        }
        return (595, 842)
    }

    private static func render(_ text: String, to url: URL, name: String) throws {
        let (pageWidth, pageHeight) = pageSize()
        let margin = 54.0
        guard let surface = cairo_pdf_surface_create(url.path, pageWidth, pageHeight),
              cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else { throw DocumentPDFError.failed(name) }
        defer { cairo_surface_destroy(surface) }
        guard let context = cairo_create(surface) else { throw DocumentPDFError.failed(name) }
        defer { cairo_destroy(context) }
        guard let layout = pango_cairo_create_layout(context) else { throw DocumentPDFError.failed(name) }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }

        if let font = pango_font_description_from_string("Monospace 10") {
            pango_layout_set_font_description(layout, font)
            pango_font_description_free(font)
        }
        pango_layout_set_width(layout, Int32((pageWidth - 2 * margin) * Double(PANGO_SCALE)))
        pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        pango_layout_set_text(layout, text, -1)

        guard let iterator = pango_layout_get_iter(layout) else { throw DocumentPDFError.failed(name) }
        defer { pango_layout_iter_free(iterator) }
        var pageTop = 0.0   // layout y (points) where this page starts
        let usable = pageHeight - 2 * margin
        repeat {
            if Task.isCancelled { throw CancellationError() }
            var logical = PangoRectangle()
            pango_layout_iter_get_line_extents(iterator, nil, &logical)
            let top = Double(logical.y) / Double(PANGO_SCALE)
            let bottom = Double(logical.y + logical.height) / Double(PANGO_SCALE)
            if bottom - pageTop > usable, top > pageTop {
                cairo_show_page(context)
                pageTop = top
            }
            let baseline = Double(pango_layout_iter_get_baseline(iterator)) / Double(PANGO_SCALE)
            cairo_move_to(context, margin, margin + baseline - pageTop)
            if let line = pango_layout_iter_get_line_readonly(iterator) {
                pango_cairo_show_layout_line(context, line)
            }
        } while pango_layout_iter_next_line(iterator) != 0
        cairo_show_page(context)
        let status = cairo_status(context)
        cairo_surface_finish(surface)
        guard status == CAIRO_STATUS_SUCCESS else { throw DocumentPDFError.failed(name) }
    }
}
