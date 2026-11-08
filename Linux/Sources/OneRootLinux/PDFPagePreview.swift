import CPopplerGLib
import Foundation

/// A PDF's first page drawn to pixels (poppler + Cairo), white paper, for the
/// Inspector and Quick Look. Runs off the main thread; nil for an unreadable
/// or password-protected file.
enum PDFPagePreview {
    static let extensions: Set<String> = ["pdf"]

    static func isPDF(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    static func firstPage(of url: URL, maxSize: Int) -> DecodedImage? {
        var error: UnsafeMutablePointer<GError>?
        guard let uri = g_filename_to_uri(url.path, nil, nil) else { return nil }
        defer { g_free(uri) }
        guard let document = poppler_document_new_from_file(uri, nil, &error) else {
            if let error { g_error_free(error) }
            return nil
        }
        defer { g_object_unref(UnsafeMutableRawPointer(document)) }
        guard poppler_document_get_n_pages(document) > 0, let page = poppler_document_get_page(document, 0) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(page)) }

        var pageWidth = 0.0, pageHeight = 0.0
        poppler_page_get_size(page, &pageWidth, &pageHeight)
        guard pageWidth > 0, pageHeight > 0 else { return nil }
        let scale = Double(maxSize) / max(pageWidth, pageHeight)
        let width = max(Int32((pageWidth * scale).rounded()), 1)
        let height = max(Int32((pageHeight * scale).rounded()), 1)

        // Raw values (CAIRO_FORMAT_RGB24 = 1, CAIRO_STATUS_SUCCESS = 0): the named
        // constants aren't visible to every toolchain's Cairo import.
        guard let surface = cairo_image_surface_create(cairo_format_t(rawValue: 1), width, height),
              cairo_surface_status(surface).rawValue == 0 else { return nil }
        defer { cairo_surface_destroy(surface) }
        guard let cr = cairo_create(surface) else { return nil }
        cairo_set_source_rgb(cr, 1, 1, 1)
        cairo_paint(cr)
        cairo_scale(cr, scale, scale)
        poppler_page_render(page, cr)
        cairo_destroy(cr)
        cairo_surface_flush(surface)

        guard let data = cairo_image_surface_get_data(surface) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(surface))
        // Cairo's RGB24 is 32-bit native-endian (B, G, R, x on little-endian);
        // repack it as plain RGB.
        var rgb = Data(count: Int(width) * Int(height) * 3)
        rgb.withUnsafeMutableBytes { out in
            for y in 0..<Int(height) {
                let row = data + y * stride
                for x in 0..<Int(width) {
                    let o = (y * Int(width) + x) * 3
                    out[o] = row[x * 4 + 2]
                    out[o + 1] = row[x * 4 + 1]
                    out[o + 2] = row[x * 4]
                }
            }
        }
        return DecodedImage(pixels: rgb, width: width, height: height, rowstride: Int(width) * 3, hasAlpha: false)
    }
}
