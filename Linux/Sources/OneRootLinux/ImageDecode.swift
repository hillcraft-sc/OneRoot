import Adwaita
import CAdwaita
import Foundation

/// An image decoded (and scaled down) off the main thread, for the
/// Inspector's preview: GdkPixbuf decoding is the slow part and is safe on
/// any thread; the pixels are copied into plain `Data` so they can cross
/// back to the main thread, where the texture is made (cheap).
struct DecodedImage: Sendable {
    let pixels: Data
    let width: Int32
    let height: Int32
    let rowstride: Int
    let hasAlpha: Bool

    /// Decodes `path` scaled to fit `maxSize` × `maxSize`; nil if it can't be read.
    static func decode(path: String, maxSize: Int) -> DecodedImage? {
        var error: UnsafeMutablePointer<GError>?
        guard let pixbuf = gdk_pixbuf_new_from_file_at_scale(path, Int32(maxSize), Int32(maxSize), 1, &error) else {
            if let error { g_error_free(error) }
            return nil
        }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        guard let bytes = gdk_pixbuf_read_pixels(pixbuf) else { return nil }
        let length = Int(gdk_pixbuf_get_byte_length(pixbuf))
        return DecodedImage(
            pixels: Data(bytes: bytes, count: length),
            width: gdk_pixbuf_get_width(pixbuf),
            height: gdk_pixbuf_get_height(pixbuf),
            rowstride: Int(gdk_pixbuf_get_rowstride(pixbuf)),
            hasAlpha: gdk_pixbuf_get_has_alpha(pixbuf) != 0
        )
    }

    /// A texture over a copy of the pixels. Main thread.
    @MainActor
    func makeTexture() -> Texture? {
        let made: UnsafeMutableRawPointer? = pixels.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UnsafeMutableRawPointer? in
            guard let base = buffer.baseAddress, let bytes = g_bytes_new(base, gsize(buffer.count)) else { return nil }
            defer { g_bytes_unref(bytes) }
            return gdk_memory_texture_new(width, height, hasAlpha ? GDK_MEMORY_R8G8B8A8 : GDK_MEMORY_R8G8B8, bytes, gsize(rowstride))
                .map { UnsafeMutableRawPointer($0) }
        }
        guard let made else { return nil }
        // The wrapper takes its own reference; ours goes.
        let texture = Texture(borrowing: made)
        g_object_unref(made)
        return texture
    }
}
