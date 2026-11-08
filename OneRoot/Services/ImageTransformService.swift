import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// UI-agnostic image transforms with ImageIO: resize, convert, and strip
/// metadata. Every method writes a new file (via `SafeFileWriter`, so an
/// existing file is never replaced) and leaves the original alone.
/// Synchronous and CPU-heavy — call off the main actor; checks for
/// cancellation between frames.
struct ImageTransformService: ImageTransforming {
    var writableFormats: [ImageFormat] { Self.writableFormats }
    var readableExtensions: Set<String> { [] }

    /// The formats this Mac's ImageIO can encode, in menu order.
    static let writableFormats: [ImageFormat] = {
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return ImageFormat.allCases.filter { writable.contains($0.type.identifier) }
    }()

    func info(for url: URL) throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ImageTransformError.unreadable(url.lastPathComponent) }

        var width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // EXIF orientations 5–8 are rotated a quarter turn: show the size
        // as the image is seen.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        return ImageInfo(
            width: width,
            height: height,
            frameCount: CGImageSourceGetCount(source),
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            format: type.flatMap(ImageFormat.init(type:)),
            metadataKinds: Self.metadataKinds(in: properties)
        )
    }

    /// The personal metadata in an image's properties: "Location", "EXIF"
    /// (camera, dates, software), "IPTC". ImageIO itself always writes a
    /// colour space, the pixel size, and the orientation and resolution —
    /// those describe the pixels, not the picture, so they don't count.
    static func metadataKinds(in properties: [CFString: Any]) -> [String] {
        func hasMore(_ key: CFString, than structural: Set<String>) -> Bool {
            guard let dictionary = properties[key] as? [String: Any] else { return false }
            return dictionary.keys.contains { !structural.contains($0) }
        }
        var kinds: [String] = []
        if hasMore(kCGImagePropertyGPSDictionary, than: []) { kinds.append("Location") }
        let exifStructural = Set([
            kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension,
        ].map { $0 as String })
        let tiffStructural = Set([
            kCGImagePropertyTIFFOrientation, kCGImagePropertyTIFFXResolution, kCGImagePropertyTIFFYResolution,
            kCGImagePropertyTIFFResolutionUnit, kCGImagePropertyTIFFCompression, kCGImagePropertyTIFFPhotometricInterpretation,
        ].map { $0 as String })
        if hasMore(kCGImagePropertyExifDictionary, than: exifStructural) || hasMore(kCGImagePropertyTIFFDictionary, than: tiffStructural) {
            kinds.append("EXIF")
        }
        if hasMore(kCGImagePropertyIPTCDictionary, than: []) { kinds.append("IPTC") }
        return kinds
    }

    /// Writes a smaller copy of `url` to `output` in the same format,
    /// every frame included. Returns where it was actually written.
    @discardableResult
    func resize(_ url: URL, to target: ImageResizeTarget, quality: Double, output: URL) throws -> URL {
        let source = try makeSource(url)
        let first = properties(source, 0)
        let width = first[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = first[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard let size = target.size(width: width, height: height),
              let type = CGImageSourceGetType(source)
        else { throw ImageTransformError.failed(output.lastPathComponent) }

        return try SafeFileWriter.write(to: output) { temporary in
            let count = CGImageSourceGetCount(source)
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, count, nil) else {
                throw ImageTransformError.failed(output.lastPathComponent)
            }
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // The orientation tag is kept, so the pixels mustn't be
                // turned as well.
                kCGImageSourceCreateThumbnailWithTransform: false,
            ]
            for index in 0..<count {
                try Task.checkCancellation()
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary) else {
                    throw ImageTransformError.unreadable(url.lastPathComponent)
                }
                var frameProperties = properties(source, index)
                Self.dropStalePixelDimensions(&frameProperties)
                frameProperties[kCGImageDestinationLossyCompressionQuality] = quality
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ImageTransformError.failed(output.lastPathComponent) }
        }
    }

    /// Writes `url` as `format` to `output`, keeping its metadata. Formats
    /// that can't hold several images get the first frame only; ones
    /// without transparency get it flattened onto white.
    @discardableResult
    func convert(_ url: URL, to format: ImageFormat, quality: Double, output: URL) throws -> URL {
        guard Self.writableFormats.contains(format) else { throw ImageTransformError.formatUnavailable(format) }
        let source = try makeSource(url)
        return try SafeFileWriter.write(to: output) { temporary in
            let count = format.supportsMultipleImages ? CGImageSourceGetCount(source) : 1
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, format.type.identifier as CFString, count, nil) else {
                throw ImageTransformError.failed(output.lastPathComponent)
            }
            for index in 0..<count {
                try Task.checkCancellation()
                guard var image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    throw ImageTransformError.unreadable(url.lastPathComponent)
                }
                if !format.supportsTransparency, Self.hasAlpha(image) {
                    image = try Self.flattenedOntoWhite(image, name: url.lastPathComponent)
                }
                var frameProperties = properties(source, index)
                if format.isLossy { frameProperties[kCGImageDestinationLossyCompressionQuality] = quality }
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ImageTransformError.failed(output.lastPathComponent) }
        }
    }

    /// Writes a copy of `url` without its EXIF, GPS, IPTC, and XMP
    /// metadata, keeping only the orientation (dropping that would turn
    /// photos on their side). Lossless where ImageIO can copy the image
    /// data as is (JPEG, PNG, TIFF); otherwise re-encoded at top quality.
    @discardableResult
    func removeMetadata(_ url: URL, output: URL) throws -> URL {
        let source = try makeSource(url)
        guard let type = CGImageSourceGetType(source) else { throw ImageTransformError.unreadable(url.lastPathComponent) }
        let orientation = properties(source, 0)[kCGImagePropertyOrientation] as? Int

        return try SafeFileWriter.write(to: output) { temporary in
            try Task.checkCancellation()
            if Self.copyWithoutMetadata(source, type: type, orientation: orientation, to: temporary) { return }
            // Fall back to re-encoding the pixels with nothing but the
            // orientation attached.
            let count = CGImageSourceGetCount(source)
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, count, nil) else {
                throw ImageTransformError.failed(output.lastPathComponent)
            }
            for index in 0..<count {
                try Task.checkCancellation()
                guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    throw ImageTransformError.unreadable(url.lastPathComponent)
                }
                var frameProperties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
                if let orientation { frameProperties[kCGImagePropertyOrientation] = orientation }
                // Animation timing isn't metadata worth losing.
                if let gif = properties(source, index)[kCGImagePropertyGIFDictionary] {
                    frameProperties[kCGImagePropertyGIFDictionary] = gif
                }
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ImageTransformError.failed(output.lastPathComponent) }
        }
    }

    // MARK: Helpers

    private func makeSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImageTransformError.unreadable(url.lastPathComponent)
        }
        return source
    }

    private func properties(_ source: CGImageSource, _ index: Int) -> [CFString: Any] {
        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
    }

    /// EXIF's own copy of the pixel size would still say the old size.
    private static func dropStalePixelDimensions(_ properties: inout [CFString: Any]) {
        guard var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return }
        exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
        exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
        properties[kCGImagePropertyExifDictionary] = exif
    }

    private static func copyWithoutMetadata(_ source: CGImageSource, type: CFString, orientation: Int?, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, CGImageSourceGetCount(source), nil) else {
            return false
        }
        // The orientation goes in as a tag of the replacement metadata:
        // `kCGImageDestinationOrientation` alongside replaced metadata makes
        // the copy fail.
        let metadata = CGImageMetadataCreateMutable()
        if let orientation {
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, orientation as CFNumber
            )
        }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return false }
        // Make sure it really went: some formats copy and keep EXIF anyway.
        guard let written = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(written, 0, nil) as? [CFString: Any]
        else { return false }
        return metadataKinds(in: properties).isEmpty
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func flattenedOntoWhite(_ image: CGImage, name: String) throws -> CGImage {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace,
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw ImageTransformError.failed(name) }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { throw ImageTransformError.failed(name) }
        return flattened
    }
}

extension QuickActionServices {
    /// ImageIO, PDFKit and the text system.
    static func mac() -> QuickActionServices {
        QuickActionServices(images: ImageTransformService(), pdfs: PDFCombineService(), documents: MacDocumentPDFConverter())
    }
}
