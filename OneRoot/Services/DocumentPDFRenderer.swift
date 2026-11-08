import AppKit

/// Word, RTF, OpenDocument text, and plain-text files as PDF — the way
/// TextEdit prints them: the document is read with macOS's text system and
/// laid out on pages of this Mac's default paper size, then printed to a
/// PDF file. Text, fonts, styles, lists, tables, and pictures come through;
/// Word's own page layout (headers and footers, columns, text boxes, exact
/// page breaks) may not.
///
/// A deliberate AppKit boundary in the service layer: the text system's
/// document reading, page layout, and printing are AppKit's. Reading runs
/// off the main thread; laying out and printing have to run on it.
enum DocumentPDFRenderer {
    /// What it reads, by extension (Pages documents need Pages; Cocoa
    /// can't read them).
    static let documentExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt", "wordml"]

    /// Writes `url` as a PDF to `output` (or a " (2)" name beside it, never
    /// over an existing file). Returns where it went.
    @MainActor
    static func convert(_ url: URL, output: URL) async throws -> URL {
        let text = try await read(url)
        try Task.checkCancellation()
        return try SafeFileWriter.write(to: output) { temporary in
            try print(text, to: temporary, name: url.lastPathComponent)
        }
    }

    /// `url` as PDF data, for Combine into PDF.
    @MainActor
    static func pdfData(for url: URL) async throws -> Data {
        let text = try await read(url)
        try Task.checkCancellation()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try print(text, to: scratch, name: url.lastPathComponent)
        return try Data(contentsOf: scratch)
    }

    /// Off the main thread: reading a document can take a moment.
    private static func read(_ url: URL) async throws -> NSAttributedString {
        let name = url.lastPathComponent
        let box = await Task.detached(priority: .userInitiated) { () -> TextBox in
            TextBox(try? NSAttributedString(url: url, options: [:], documentAttributes: nil))
        }.value
        guard let text = box.text else { throw DocumentPDFError.unreadable(name) }
        return text
    }

    @MainActor
    private static func print(_ text: NSAttributedString, to url: URL, name: String) throws {
        guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else { throw DocumentPDFError.failed(name) }
        let margin: CGFloat = 54 // ¾ inch, as TextEdit prints
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        // Start at the top of the page, not centred, however short it is.
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentPDFError.failed(name)
        }
    }
}

/// Carries the read document from the reading thread to the main actor;
/// nothing touches it in between.
private final class TextBox: @unchecked Sendable {
    let text: NSAttributedString?
    init(_ text: NSAttributedString?) { self.text = text }
}

/// `DocumentPDFRenderer` behind the platform-neutral protocol.
struct MacDocumentPDFConverter: DocumentPDFConverting {
    var documentExtensions: Set<String> { DocumentPDFRenderer.documentExtensions }
    @MainActor func convert(_ url: URL, output: URL) async throws -> URL {
        try await DocumentPDFRenderer.convert(url, output: output)
    }
    @MainActor func pdfData(for url: URL) async throws -> Data {
        try await DocumentPDFRenderer.pdfData(for: url)
    }
}
