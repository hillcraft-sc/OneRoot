import CAdwaita
import Foundation
@testable import OneRoot

/// Quick Actions' image work on Linux, with GdkPixbuf: resize, convert, and
/// metadata removal. Every method writes a new file through `SafeFileWriter`
/// (never over an existing one). Differences from the Mac's ImageIO service,
/// all stated in the sheets and docs: GdkPixbuf writes no metadata, so
/// resized and converted copies carry none (a privacy gain, but not "kept");
/// animated images and multi-page TIFFs keep their first frame; HEIC can be
/// read (if a loader is installed) but not written. Metadata removal is
/// lossless for JPEG and PNG (`ImageMetadata`).
struct LinuxImageTransformService: ImageTransforming {
    var writableFormats: [ImageFormat] {
        ImageFormat.allCases.filter { Self.pixbufType(for: $0) != nil && Self.isWritable(Self.pixbufType(for: $0) ?? "") }
    }

    var readableExtensions: Set<String> { Self.readable }

    // MARK: Formats

    private static let readable: Set<String> = {
        var extensions: Set<String> = []
        var node = gdk_pixbuf_get_formats()
        let head = node
        while let item = node {
            if let format = item.pointee.data.map { OpaquePointer($0) },
               gdk_pixbuf_format_is_disabled(format) == 0, let list = gdk_pixbuf_format_get_extensions(format) {
                var index = 0
                while let entry = list[index] {
                    extensions.insert(String(cString: entry).lowercased())
                    index += 1
                }
                g_strfreev(list)
            }
            node = item.pointee.next
        }
        g_slist_free(head)
        // SVG is a drawing, not a photo to resize.
        extensions.remove("svg")
        extensions.remove("svgz")
        return extensions
    }()

    private static func pixbufType(for format: ImageFormat) -> String? {
        switch format {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heic: return nil
        }
    }

    private static func isWritable(_ type: String) -> Bool {
        var node = gdk_pixbuf_get_formats()
        let head = node
        defer { g_slist_free(head) }
        while let item = node {
            if let format = item.pointee.data.map { OpaquePointer($0) },
               let name = gdk_pixbuf_format_get_name(format) {
                let found = String(cString: name) == type
                g_free(name)
                if found { return gdk_pixbuf_format_is_writable(format) != 0 }
            }
            node = item.pointee.next
        }
        return false
    }

    static func format(forName name: String) -> ImageFormat? {
        ImageFormat.allCases.first { pixbufType(for: $0) == name }
    }

    /// The saver GdkPixbuf needs for a file extension.
    static func pixbufType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "jpg", "jpeg", "jpe": return "jpeg"
        case "png": return "png"
        case "tif", "tiff": return "tiff"
        default: return nil
        }
    }

    // MARK: Info

    func info(for url: URL) throws -> ImageInfo {
        var width: Int32 = 0
        var height: Int32 = 0
        guard let format = gdk_pixbuf_get_file_info(url.path, &width, &height), width > 0, height > 0,
              let nameC = gdk_pixbuf_format_get_name(format) else {
            throw ImageTransformError.unreadable(url.lastPathComponent)
        }
        let name = String(cString: nameC)
        g_free(nameC)

        let report = Self.report(for: url)
        var pixelWidth = Int(width)
        var pixelHeight = Int(height)
        if let orientation = report.orientation, (5...8).contains(orientation) { swap(&pixelWidth, &pixelHeight) }

        var hasAlpha = false
        if name != "jpeg" {
            // A small decode is the only way to ask a pixbuf loader.
            var error: UnsafeMutablePointer<GError>?
            if let small = gdk_pixbuf_new_from_file_at_scale(url.path, 32, 32, 1, &error) {
                hasAlpha = gdk_pixbuf_get_has_alpha(small) != 0
                g_object_unref(UnsafeMutableRawPointer(small))
            } else if let error {
                g_error_free(error)
            }
        }
        var frames = 1
        if name == "gif" || name == "webp" || name == "png" {
            var error: UnsafeMutablePointer<GError>?
            if let animation = gdk_pixbuf_animation_new_from_file(url.path, &error) {
                if gdk_pixbuf_animation_is_static_image(animation) == 0 { frames = 2 }
                g_object_unref(UnsafeMutableRawPointer(animation))
            } else if let error {
                g_error_free(error)
            }
        }
        return ImageInfo(
            width: pixelWidth, height: pixelHeight, frameCount: frames, hasAlpha: hasAlpha,
            format: Self.format(forName: name), metadataKinds: report.kinds
        )
    }

    /// The head of the file is where metadata lives (a PNG's can follow the
    /// pixels, but that is rare enough to leave).
    private static func report(for url: URL) -> ImageMetadata.Report {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ImageMetadata.Report() }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1 << 20) else { return ImageMetadata.Report() }
        return ImageMetadata.inspect(head)
    }

    // MARK: Transforms

    @discardableResult
    func resize(_ url: URL, to target: ImageResizeTarget, quality: Double, output: URL) throws -> URL {
        var width: Int32 = 0
        var height: Int32 = 0
        guard gdk_pixbuf_get_file_info(url.path, &width, &height) != nil else { throw ImageTransformError.unreadable(url.lastPathComponent) }
        let upright = Self.report(for: url).orientation.map { (5...8).contains($0) } ?? false
        guard let size = target.size(width: upright ? Int(height) : Int(width), height: upright ? Int(width) : Int(height)) else {
            throw ImageTransformError.failed(output.lastPathComponent)
        }
        guard Self.pixbufType(forExtension: output.pathExtension) != nil else {
            throw ImageTransformError.failed(output.lastPathComponent)
        }
        return try SafeFileWriter.write(to: output) { temporary in
            try Task.checkCancellation()
            let pixbuf = try Self.load(url, maxSize: max(size.width, size.height))
            defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
            try Self.save(pixbuf, to: temporary, quality: quality, name: output.lastPathComponent)
        }
    }

    @discardableResult
    func convert(_ url: URL, to format: ImageFormat, quality: Double, output: URL) throws -> URL {
        guard writableFormats.contains(format) else { throw ImageTransformError.formatUnavailable(format) }
        return try SafeFileWriter.write(to: output) { temporary in
            try Task.checkCancellation()
            var pixbuf = try Self.load(url, maxSize: nil)
            defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
            if !format.supportsTransparency, gdk_pixbuf_get_has_alpha(pixbuf) != 0 {
                let width = gdk_pixbuf_get_width(pixbuf)
                let height = gdk_pixbuf_get_height(pixbuf)
                guard let flat = gdk_pixbuf_composite_color_simple(pixbuf, width, height, GDK_INTERP_BILINEAR, 255, 1, 0xFFFFFFFF, 0xFFFFFFFF) else {
                    throw ImageTransformError.failed(output.lastPathComponent)
                }
                g_object_unref(UnsafeMutableRawPointer(pixbuf))
                pixbuf = flat
            }
            try Self.save(pixbuf, to: temporary, quality: quality, name: output.lastPathComponent)
        }
    }

    @discardableResult
    func removeMetadata(_ url: URL, output: URL) throws -> URL {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch { throw ImageTransformError.unreadable(url.lastPathComponent) }
        let report = ImageMetadata.inspect(data)
        return try SafeFileWriter.write(to: output) { temporary in
            try Task.checkCancellation()
            // JPEG and PNG: the same bytes minus the metadata.
            if let stripped = ImageMetadata.strippedJPEG(data, orientation: report.orientation) ?? ImageMetadata.strippedPNG(data) {
                try stripped.write(to: temporary)
                return
            }
            // Anything else: re-encoded at top quality (no metadata is written).
            guard Self.pixbufType(forExtension: output.pathExtension) != nil else { throw ImageTransformError.failed(output.lastPathComponent) }
            let pixbuf = try Self.load(url, maxSize: nil)
            defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
            try Self.save(pixbuf, to: temporary, quality: 1, name: output.lastPathComponent)
        }
    }

    // MARK: GdkPixbuf

    /// Loads `url` turned the right way up, scaled to fit `maxSize` if given.
    /// The caller owns the result.
    private static func load(_ url: URL, maxSize: Int?) throws -> OpaquePointer {
        var error: UnsafeMutablePointer<GError>?
        let loaded: OpaquePointer?
        if let maxSize {
            loaded = gdk_pixbuf_new_from_file_at_scale(url.path, Int32(maxSize), Int32(maxSize), 1, &error)
        } else {
            loaded = gdk_pixbuf_new_from_file(url.path, &error)
        }
        guard let loaded else {
            if let error { g_error_free(error) }
            throw ImageTransformError.unreadable(url.lastPathComponent)
        }
        // Metadata isn't written, so the orientation can't be kept as a tag:
        // the pixels are turned instead.
        guard let upright = gdk_pixbuf_apply_embedded_orientation(loaded) else { return loaded }
        g_object_unref(UnsafeMutableRawPointer(loaded))
        return upright
    }

    private static func save(_ pixbuf: OpaquePointer, to url: URL, quality: Double, name: String) throws {
        guard let type = pixbufType(forExtension: url.pathExtension) else { throw ImageTransformError.failed(name) }
        var error: UnsafeMutablePointer<GError>?
        var ok: gboolean = 0
        if type == "jpeg" {
            let percent = String(Int((min(max(quality, 0.01), 1) * 100).rounded()))
            var key: UnsafeMutablePointer<CChar>? = strdup("quality")
            var value: UnsafeMutablePointer<CChar>? = strdup(percent)
            defer { free(key); free(value) }
            var keys: [UnsafeMutablePointer<CChar>?] = [key, nil]
            var values: [UnsafeMutablePointer<CChar>?] = [value, nil]
            ok = gdk_pixbuf_savev(pixbuf, url.path, type, &keys, &values, &error)
            key = nil
            value = nil
        } else {
            ok = gdk_pixbuf_savev(pixbuf, url.path, type, nil, nil, &error)
        }
        guard ok != 0 else {
            if let error { g_error_free(error) }
            throw ImageTransformError.failed(name)
        }
    }
}
