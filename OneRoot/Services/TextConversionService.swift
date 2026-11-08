import Foundation

/// What a text Quick Action's preview needs to know about a file.
struct TextInfo: Equatable {
    let lineCount: Int
}

enum TextConversionError: LocalizedError {
    case unreadable(String)
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "“\(name)” couldn't be read as text."
        case .tooLarge(let name): return "“\(name)” is too large to convert (over 20 MB)."
        }
    }
}

/// UI-agnostic text conversions: plain text to Markdown, Markdown to
/// HTML (`MarkdownHTMLRenderer`), HTML to Markdown
/// (`HTMLMarkdownConverter`). Outputs are UTF-8, written with
/// `SafeFileWriter` beside the original. Synchronous — call off the main
/// actor.
struct TextConversionService {
    /// Text files bigger than this are left alone: they're logs or data,
    /// not documents, and reading them whole would take a lot of memory.
    static let maximumSize = 20_000_000

    func info(for url: URL) throws -> TextInfo {
        let text = try readText(url)
        return TextInfo(lineCount: text.isEmpty ? 0 : text.components(separatedBy: .newlines).count)
    }

    /// The converted text of `url`, for `request` (a text conversion).
    func convertedText(of url: URL, for request: QuickActionRequest) throws -> String {
        switch request {
        case .textToMarkdown(let keepLineBreaks, let escapeSymbols):
            return markdown(fromPlainText: try readText(url), keepLineBreaks: keepLineBreaks, escapeSymbols: escapeSymbols)
        case .markdownToHTML(let styled):
            let markdown = try readText(url)
            let title = Self.firstHeading(in: markdown) ?? url.deletingPathExtension().lastPathComponent
            return try MarkdownHTMLRenderer().document(fromMarkdown: markdown, title: title, styled: styled)
        case .htmlToMarkdown:
            do {
                return try HTMLMarkdownConverter().markdown(fromHTML: try readText(url))
            } catch is HTMLMarkdownError {
                throw TextConversionError.unreadable(url.lastPathComponent)
            }
        case .resize, .convert, .removeMetadata, .combine, .convertToPDF:
            throw TextConversionError.unreadable(url.lastPathComponent)
        }
    }

    @discardableResult
    func convert(_ url: URL, for request: QuickActionRequest, output: URL) throws -> URL {
        let text = try convertedText(of: url, for: request)
        try Task.checkCancellation()
        return try SafeFileWriter.write(to: output) { temporary in
            try Data(text.utf8).write(to: temporary)
        }
    }

    /// Plain text as Markdown. Blank lines still separate paragraphs;
    /// with `keepLineBreaks`, every other line break stays one (a trailing
    /// double space — invisible if the line turns out to start a list).
    /// With `escapeSymbols`, nothing in the text turns into formatting.
    func markdown(fromPlainText text: String, keepLineBreaks: Bool, escapeSymbols: Bool) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [[String]] = [[]]
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !(paragraphs.last?.isEmpty ?? true) { paragraphs.append([]) }
            } else {
                var line = line
                while line.last?.isWhitespace ?? false { line.removeLast() }
                if escapeSymbols {
                    // Leading spaces would make an indented code block.
                    let indent = line.prefix { $0 == " " || $0 == "\t" }
                    let rest = String(line.dropFirst(indent.count))
                    line = String(repeating: "&nbsp;", count: indent.count) + HTMLMarkdownConverter.escapeLineStart(HTMLMarkdownConverter.escape(rest))
                }
                paragraphs[paragraphs.count - 1].append(line)
            }
        }
        let body = paragraphs.filter { !$0.isEmpty }
            .map { $0.joined(separator: keepLineBreaks ? "  \n" : "\n") }
            .joined(separator: "\n\n")
        return body.isEmpty ? "" : body + "\n"
    }

    // MARK: Reading

    private func readData(_ url: URL) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumSize else { throw TextConversionError.tooLarge(url.lastPathComponent) }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TextConversionError.unreadable(url.lastPathComponent)
        }
    }

    /// UTF-8 (or a BOM'd UTF-16) first, then the usual Mac and Windows
    /// encodings older text files come in.
    private func readText(_ url: URL) throws -> String {
        let data = try readData(url)
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252, .macOSRoman] {
            if encoding == .utf16, !(data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])) { continue }
            if var text = String(data: data, encoding: encoding) {
                if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
                // Not text at all (a binary file with a .txt name).
                if text.contains("\u{0}") { break }
                return text
            }
        }
        throw TextConversionError.unreadable(url.lastPathComponent)
    }

    /// "Title" from a leading "# Title", for the HTML page's title.
    static func firstHeading(in markdown: String) -> String? {
        for line in markdown.split(separator: "\n", maxSplits: 50) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }
}
