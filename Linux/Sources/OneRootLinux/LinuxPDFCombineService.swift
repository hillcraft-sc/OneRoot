import CAdwaita
import CPangoCairoPDF
import CQPDF
import Foundation
@testable import OneRoot

/// Combine into PDF on Linux: qpdf joins whole PDFs (pages, links and
/// annotations come along untouched, nothing is re-rendered); an image
/// first becomes a one-page PDF through Cairo, drawn upright at 72 pixels
/// per inch (the Mac's rule too when an image states no resolution).
/// Password-protected PDFs are refused, as on the Mac.
struct LinuxPDFCombineService: PDFCombining {
    func pageCount(of url: URL) -> Int? {
        if Self.isPDF(url) {
            if case .pages(let count) = Self.inspect(url) { return count }
            return nil
        }
        var width: Int32 = 0
        var height: Int32 = 0
        return gdk_pixbuf_get_file_info(url.path, &width, &height) != nil ? 1 : nil
    }

    @discardableResult
    func combine(_ sources: [URL], output: URL, progress: (Int) -> Void) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("oneroot-combine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var files: [String] = []
        for (index, url) in sources.enumerated() {
            try Task.checkCancellation()
            progress(index)
            if Self.isPDF(url) {
                switch Self.inspect(url) {
                case .pages: files.append(url.path)
                case .locked: throw PDFCombineError.locked(url.lastPathComponent)
                case .unreadable: throw PDFCombineError.unreadable(url.lastPathComponent)
                }
            } else {
                let page = scratch.appendingPathComponent("\(index).pdf")
                try Self.writeImagePage(from: url, to: page)
                files.append(page.path)
            }
        }
        try Task.checkCancellation()
        return try SafeFileWriter.write(to: output) { temporary in
            guard Self.runQPDF(merging: files, into: temporary.path) else { throw PDFCombineError.failed(output.lastPathComponent) }
        }
    }

    // MARK: qpdf

    private enum Inspection {
        case pages(Int)
        case locked
        case unreadable
    }

    /// Anything with a PDF's first bytes — not just a ".pdf" name.
    private static func isPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1024) else { return false }
        return head.range(of: Data("%PDF-".utf8)) != nil
    }

    private static func inspect(_ url: URL) -> Inspection {
        guard let qpdf = qpdf_init() else { return .unreadable }
        var handle: qpdf_data? = qpdf
        defer { qpdf_cleanup(&handle) }
        let status = qpdf_read(qpdf, url.path, nil)
        if status & QPDF_ERRORS != 0 {
            if let error = qpdf_get_error(qpdf), qpdf_get_error_code(qpdf, error) == qpdf_e_password { return .locked }
            return .unreadable
        }
        let count = Int(qpdf_get_num_pages(qpdf))
        return count > 0 ? .pages(count) : .unreadable
    }

    /// `qpdf --empty --pages a b … -- out`, in this process. Exit 0 is
    /// success and 3 is "written, with warnings".
    private static func runQPDF(merging files: [String], into output: String) -> Bool {
        var arguments = ["qpdf", "--empty", "--pages"] + files + ["--", output]
        // Page ranges default to all pages; an input named like an option
        // can't be misread because each goes through as its own argument
        // after `--pages`, but a leading "-" would: protect it.
        arguments = arguments.map { $0.hasPrefix("-") && !["--empty", "--pages", "--"].contains($0) ? "./" + $0 : $0 }
        var argv: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) }
        argv.append(nil)
        defer { for pointer in argv { free(UnsafeMutablePointer(mutating: pointer)) } }
        let status = qpdfjob_run_from_argv(argv)
        return status == 0 || status == 3
    }

    // MARK: Images

    /// A one-page PDF the size of the picture, turned upright.
    private static func writeImagePage(from url: URL, to page: URL) throws {
        var error: UnsafeMutablePointer<GError>?
        guard let loaded = gdk_pixbuf_new_from_file(url.path, &error) else {
            if let error { g_error_free(error) }
            throw PDFCombineError.unreadable(url.lastPathComponent)
        }
        defer { g_object_unref(UnsafeMutableRawPointer(loaded)) }
        let upright = gdk_pixbuf_apply_embedded_orientation(loaded)
        defer { if let upright { g_object_unref(UnsafeMutableRawPointer(upright)) } }
        let pixbuf = upright ?? loaded
        let width = Double(gdk_pixbuf_get_width(pixbuf))
        let height = Double(gdk_pixbuf_get_height(pixbuf))
        guard let surface = cairo_pdf_surface_create(page.path, width, height) else {
            throw PDFCombineError.failed(url.lastPathComponent)
        }
        defer { cairo_surface_destroy(surface) }
        guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS, let context = cairo_create(surface) else {
            throw PDFCombineError.failed(url.lastPathComponent)
        }
        gdk_cairo_set_source_pixbuf(context, pixbuf, 0, 0)
        cairo_paint(context)
        cairo_show_page(context)
        let status = cairo_status(context)
        cairo_destroy(context)
        cairo_surface_finish(surface)
        guard status == CAIRO_STATUS_SUCCESS else { throw PDFCombineError.failed(url.lastPathComponent) }
    }
}
