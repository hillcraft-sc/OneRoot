import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A file transform offered for the selection — Context Bar ▸ Quick
/// Actions ▾ and the context menu. Each one writes *new* files beside the
/// originals (never over them) after a preview, and is undoable. Which
/// ones apply to a selection is `QuickActionCatalog`'s call.
enum QuickAction: String, CaseIterable, Identifiable {
    case resizeImages
    case convertImages
    case removeImageMetadata
    case combineIntoPDF
    case textToMarkdown
    case markdownToHTML
    case htmlToMarkdown
    case convertToPDF

    var id: Self { self }

    /// Menu title, with the ellipsis — every action opens its sheet first.
    var menuTitle: String {
        switch self {
        case .resizeImages: return "Resize Images\u{2026}"
        case .convertImages: return "Convert Images\u{2026}"
        case .removeImageMetadata: return "Remove Metadata\u{2026}"
        case .combineIntoPDF: return "Combine into PDF\u{2026}"
        case .textToMarkdown: return "Text to Markdown\u{2026}"
        case .markdownToHTML: return "Markdown to HTML\u{2026}"
        case .htmlToMarkdown: return "HTML to Markdown\u{2026}"
        case .convertToPDF: return "Convert to PDF\u{2026}"
        }
    }

    var systemImage: String {
        switch self {
        case .resizeImages: return "arrow.up.left.and.arrow.down.right"
        case .convertImages: return "photo.on.rectangle.angled"
        case .removeImageMetadata: return "location.slash"
        case .combineIntoPDF: return "doc.on.doc"
        case .textToMarkdown, .htmlToMarkdown: return "text.badge.checkmark"
        case .markdownToHTML: return "chevron.left.forwardslash.chevron.right"
        case .convertToPDF: return "doc.richtext"
        }
    }

    /// "Resize", "Convert", … — the verb in progress titles and Undo.
    var verb: String {
        switch self {
        case .resizeImages: return "Resize"
        case .convertImages: return "Convert"
        case .removeImageMetadata: return "Remove Metadata from"
        case .combineIntoPDF: return "Combine"
        case .textToMarkdown, .markdownToHTML, .htmlToMarkdown, .convertToPDF: return "Convert"
        }
    }

    /// Works on text files (the rest work on images and PDFs).
    var isTextConversion: Bool {
        switch self {
        case .textToMarkdown, .markdownToHTML, .htmlToMarkdown: return true
        case .resizeImages, .convertImages, .removeImageMetadata, .combineIntoPDF, .convertToPDF: return false
        }
    }
}

/// An image format OneRoot can write, when ImageIO on this Mac can (HEIC
/// needs a hardware encoder — see `ImageTransformService.writableFormats`).
enum ImageFormat: String, CaseIterable, Identifiable {
    case jpeg, png, heic, tiff

    var id: Self { self }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    #if canImport(UniformTypeIdentifiers)
    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }
    #endif

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    /// Takes a quality setting (and loses detail doing it).
    var isLossy: Bool { self == .jpeg || self == .heic }
    var supportsTransparency: Bool { self != .jpeg }
    /// Can hold every frame of an animated GIF or multi-page TIFF.
    var supportsMultipleImages: Bool { self == .tiff || self == .heic }

    #if canImport(UniformTypeIdentifiers)
    /// The format of a file of `type`, if it's one of these.
    init?(type: UTType) {
        guard let format = Self.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = format
    }
    #endif
}

/// How big resized images should be. Never enlarges.
enum ImageResizeTarget: Equatable {
    /// The longer side, in pixels.
    case longestSide(Int)
    /// 1–99 percent of each side.
    case percent(Int)

    /// The new pixel size for an image of `width`×`height`, or `nil` when
    /// it's already that small.
    func size(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let scale: Double
        switch self {
        case .longestSide(let side):
            scale = Double(side) / Double(max(width, height))
        case .percent(let percent):
            scale = Double(percent) / 100
        }
        guard scale < 1, scale > 0 else { return nil }
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        return (newWidth, newHeight)
    }
}

/// What to do, fully specified — what a Quick Action sheet hands back.
enum QuickActionRequest: Equatable {
    /// `quality` 0…1, for lossy formats.
    case resize(ImageResizeTarget, quality: Double)
    case convert(to: ImageFormat, quality: Double)
    case removeMetadata
    /// `name` without the ".pdf".
    case combine(name: String)
    /// `keepLineBreaks`: each line stays a line (Markdown otherwise joins
    /// lines into paragraphs). `escapeSymbols`: `*`, `#`, `-`, … show as
    /// written instead of becoming formatting.
    case textToMarkdown(keepLineBreaks: Bool, escapeSymbols: Bool)
    /// `styled`: a page with simple, light/dark-aware styling.
    case markdownToHTML(styled: Bool)
    case htmlToMarkdown
    /// Word, RTF, OpenDocument, or plain text, printed to PDF.
    case convertToPDF

    var action: QuickAction {
        switch self {
        case .resize: return .resizeImages
        case .convert: return .convertImages
        case .removeMetadata: return .removeImageMetadata
        case .combine: return .combineIntoPDF
        case .textToMarkdown: return .textToMarkdown
        case .markdownToHTML: return .markdownToHTML
        case .htmlToMarkdown: return .htmlToMarkdown
        case .convertToPDF: return .convertToPDF
        }
    }
}

/// A Quick Action waiting on its sheet — `FileListViewModel.pendingQuickAction`.
struct PendingQuickAction: Identifiable, Equatable {
    let id = UUID()
    let action: QuickAction
    let urls: [URL]
}

// MARK: - What a platform provides

/// What a Quick Action's preview needs to know about an image — read from
/// its header only, so it's quick even for big photos.
struct ImageInfo: Equatable {
    let width: Int
    let height: Int
    /// More than 1 for animated GIFs and multi-page TIFFs.
    let frameCount: Int
    let hasAlpha: Bool
    /// `nil` for formats OneRoot can read but not write (GIF, BMP, RAW…).
    let format: ImageFormat?
    /// Which kinds of metadata it carries: "Location", "EXIF", "IPTC".
    let metadataKinds: [String]
}

enum ImageTransformError: LocalizedError {
    case unreadable(String)
    case formatUnavailable(ImageFormat)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "\u{201C}\(name)\u{201D} couldn't be read as an image."
        case .formatUnavailable(let format):
            #if canImport(Darwin)
            return "This Mac can't write \(format.title) images."
            #else
            return "This computer can't write \(format.title) images."
            #endif
        case .failed(let name):
            return "Couldn't write \u{201C}\(name)\u{201D}."
        }
    }
}

enum PDFCombineError: LocalizedError {
    case unreadable(String)
    case locked(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "\u{201C}\(name)\u{201D} couldn't be read as a PDF or an image."
        case .locked(let name):
            #if canImport(Darwin)
            return "\u{201C}\(name)\u{201D} is password-protected. Open it in Preview to remove the password, then try again."
            #else
            return "\u{201C}\(name)\u{201D} is password-protected. Remove the password in another PDF app, then try again."
            #endif
        case .failed(let name):
            return "Couldn't write \u{201C}\(name)\u{201D}."
        }
    }
}

enum DocumentPDFError: LocalizedError {
    case unreadable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "\u{201C}\(name)\u{201D} couldn't be read as a document."
        case .failed(let name): return "Couldn't make a PDF of \u{201C}\(name)\u{201D}."
        }
    }
}

/// Image resize / convert / metadata removal. macOS: ImageIO
/// (`ImageTransformService`); Linux: GdkPixbuf. Synchronous and CPU-heavy —
/// called off the main actor; checks for cancellation between frames.
protocol ImageTransforming: Sendable {
    /// The formats this computer can write, in menu order.
    var writableFormats: [ImageFormat] { get }
    /// File extensions (lowercase) it can read as images. Used where file
    /// types can't be asked of the system (Linux).
    var readableExtensions: Set<String> { get }
    func info(for url: URL) throws -> ImageInfo
    @discardableResult func resize(_ url: URL, to target: ImageResizeTarget, quality: Double, output: URL) throws -> URL
    @discardableResult func convert(_ url: URL, to format: ImageFormat, quality: Double, output: URL) throws -> URL
    @discardableResult func removeMetadata(_ url: URL, output: URL) throws -> URL
}

/// Combining PDFs and images into one PDF. macOS: PDFKit; Linux: qpdf.
protocol PDFCombining: Sendable {
    /// Pages `url` will add; `nil` when unreadable or locked.
    func pageCount(of url: URL) -> Int?
    @discardableResult func combine(_ sources: [URL], output: URL, progress: (Int) -> Void) throws -> URL
}

/// Documents printed to PDF. macOS: Word, RTF, OpenDocument and plain text
/// through the text system; Linux: plain text.
protocol DocumentPDFConverting: Sendable {
    /// Extensions (beyond plain text) it reads, lowercase.
    var documentExtensions: Set<String> { get }
    @MainActor func convert(_ url: URL, output: URL) async throws -> URL
    @MainActor func pdfData(for url: URL) async throws -> Data
}

/// The services Quick Actions use. The Mac app builds its own at launch
/// (`ImageTransformService.swift`); the Linux app installs `current` at
/// startup. Where nothing is installed, actions report they can't run.
struct QuickActionServices: Sendable {
    var images: any ImageTransforming
    var pdfs: any PDFCombining
    var documents: any DocumentPDFConverting

    nonisolated(unsafe) static var current: QuickActionServices = {
        #if os(macOS) && !SWIFT_PACKAGE
        return .mac()
        #else
        return QuickActionServices(images: UnavailableServices(), pdfs: UnavailableServices(), documents: UnavailableServices())
        #endif
    }()
}

/// Stands in until a platform installs real services.
struct UnavailableServices: ImageTransforming, PDFCombining, DocumentPDFConverting {
    var writableFormats: [ImageFormat] { [] }
    var readableExtensions: Set<String> { [] }
    var documentExtensions: Set<String> { [] }
    func info(for url: URL) throws -> ImageInfo { throw ImageTransformError.unreadable(url.lastPathComponent) }
    func resize(_ url: URL, to target: ImageResizeTarget, quality: Double, output: URL) throws -> URL { throw ImageTransformError.failed(output.lastPathComponent) }
    func convert(_ url: URL, to format: ImageFormat, quality: Double, output: URL) throws -> URL { throw ImageTransformError.formatUnavailable(format) }
    func removeMetadata(_ url: URL, output: URL) throws -> URL { throw ImageTransformError.failed(output.lastPathComponent) }
    func pageCount(of url: URL) -> Int? { nil }
    func combine(_ sources: [URL], output: URL, progress: (Int) -> Void) throws -> URL { throw PDFCombineError.failed(output.lastPathComponent) }
    @MainActor func convert(_ url: URL, output: URL) async throws -> URL { throw DocumentPDFError.failed(url.lastPathComponent) }
    @MainActor func pdfData(for url: URL) async throws -> Data { throw DocumentPDFError.failed(url.lastPathComponent) }
}
