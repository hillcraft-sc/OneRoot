import Foundation
#if canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

/// A Quick Action as offered for one selection: either it applies to every
/// selected item, or it applies to some and `unavailableReason` says why
/// it's switched off (shown disabled, rather than silently acting on part
/// of the selection).
struct QuickActionOption: Equatable, Identifiable {
    let action: QuickAction
    let unavailableReason: String?

    var id: QuickAction { action }
    var isAvailable: Bool { unavailableReason == nil }
}

/// The selection-capability model: which Quick Actions make sense for a
/// selection (images, PDFs, plain text, Markdown, HTML), judged from file
/// types alone (no disk reads, so it's cheap enough to run on every
/// selection change).
struct QuickActionCatalog {
    private let services: QuickActionServices

    #if canImport(UniformTypeIdentifiers)
    /// Type identifiers ImageIO can read — injectable for tests.
    private let readableImageTypes: Set<String>

    init(readableImageTypes: Set<String>? = nil, services: QuickActionServices = .current) {
        self.readableImageTypes = readableImageTypes ?? Self.systemReadableImageTypes
        self.services = services
    }

    static let systemReadableImageTypes: Set<String> = {
        Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    }()
    #else
    init(services: QuickActionServices = .current) {
        self.services = services
    }
    #endif

    /// The actions relevant to `nodes`, in menu order — empty when none
    /// is (the menu then doesn't show at all).
    func options(for nodes: [FileNode]) -> [QuickActionOption] {
        guard !nodes.isEmpty else { return [] }
        let kinds = nodes.map(kind(of:))
        let imageCount = kinds.filter { $0 == .image }.count
        let pdfCount = kinds.filter { $0 == .pdf }.count
        // Word/RTF/OpenDocument and plain text — what prints to PDF.
        let documentCount = kinds.filter { $0 == .document || $0 == .plainText }.count

        var options: [QuickActionOption] = []
        if imageCount > 0 {
            let reason = imageCount == nodes.count ? nil : "Select only images to use this"
            options.append(QuickActionOption(action: .resizeImages, unavailableReason: reason))
            options.append(QuickActionOption(action: .convertImages, unavailableReason: reason))
            options.append(QuickActionOption(action: .removeImageMetadata, unavailableReason: reason))
        }
        if documentCount > 0 {
            let reason = documentCount == nodes.count ? nil : "Select only documents (Word, RTF, text) to use this"
            options.append(QuickActionOption(action: .convertToPDF, unavailableReason: reason))
        }
        // One PDF on its own has nothing to combine with; one document can
        // be combined (it's converted), though Convert to PDF says it better.
        if imageCount > 0 || pdfCount > 1 || (documentCount > 0 && nodes.count > 1) {
            let reason = imageCount + pdfCount + documentCount == nodes.count ? nil : "Select only PDFs, images, and documents to use this"
            options.append(QuickActionOption(action: .combineIntoPDF, unavailableReason: reason))
        }
        for (kind, action, noun) in [(Kind.plainText, QuickAction.textToMarkdown, "text files"), (.markdown, .markdownToHTML, "Markdown files"), (.html, .htmlToMarkdown, "HTML files")] {
            let count = kinds.filter { $0 == kind }.count
            guard count > 0 else { continue }
            options.append(QuickActionOption(action: action, unavailableReason: count == nodes.count ? nil : "Select only \(noun) to use this"))
        }
        return options
    }

    enum Kind: Equatable {
        case image, pdf, document, plainText, markdown, html, other
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    func kind(of node: FileNode) -> Kind {
        guard !node.isDirectory else { return .other }
        let ext = node.fileExtension.lowercased()
        // Checked by extension: not every Mac declares a Markdown type.
        if Self.markdownExtensions.contains(ext) { return .markdown }
        if services.documents.documentExtensions.contains(ext) { return .document }
        #if canImport(UniformTypeIdentifiers)
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image), readableImageTypes.contains(type.identifier) { return .image }
        if type.conforms(to: .html) { return .html }
        // Plain text, but not source code or data formats (JSON, CSV…),
        // which have Markdown of their own to be written in.
        if type.conforms(to: .plainText), !type.conforms(to: .sourceCode), !type.conforms(to: .commaSeparatedText),
           !type.conforms(to: .tabSeparatedText), !type.conforms(to: .json), !type.conforms(to: .xml) {
            return .plainText
        }
        return .other
        #else
        // No type database to ask: by extension.
        if ext == "pdf" { return .pdf }
        if services.images.readableExtensions.contains(ext) { return .image }
        if ext == "html" || ext == "htm" || ext == "xhtml" { return .html }
        if Self.plainTextExtensions.contains(ext) { return .plainText }
        return .other
        #endif
    }

    /// Plain text proper — not source code or data formats.
    static let plainTextExtensions: Set<String> = ["txt", "text", "log"]
}
