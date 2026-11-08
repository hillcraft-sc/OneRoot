import Foundation

/// What a Quick Action will do with one selected item — the sheet's
/// preview row, and what `QuickActionRunner` then carries out.
struct QuickActionPlanItem: Identifiable, Equatable {
    enum Outcome: Equatable {
        /// Writes a new file here.
        case write(URL)
        /// Goes into the combined PDF.
        case include
        /// Left alone, for this reason.
        case skip(String)
    }

    let source: URL
    /// "4032 × 3024 → 1600 × 1200", "3 pages", …
    let detail: String
    let outcome: Outcome
    /// A caveat about this item that doesn't stop it: "First frame only".
    let note: String?

    var id: URL { source }

    var output: URL? {
        if case .write(let url) = outcome { return url }
        return nil
    }

    var isSkipped: Bool {
        if case .skip = outcome { return true }
        return false
    }
}

struct QuickActionPlan: Equatable {
    let items: [QuickActionPlanItem]
    /// Combine into PDF only: the one file it writes.
    let combinedOutput: URL?
    /// Things to know before going ahead — lossy re-encoding, transparency.
    let warnings: [String]
    /// Sources that are documents (Word, RTF, text): printed to PDF first.
    var documents: Set<URL> = []

    /// Nothing would be written.
    var isEmpty: Bool {
        if items.contains(where: { $0.outcome == .include }) { return combinedOutput == nil }
        return items.allSatisfy(\.isSkipped)
    }
}

/// Works out, before anything is written, what each Quick Action will
/// produce: output names (new, never an existing file's — " (2)" like
/// Keep Both), what gets skipped and why, and what's lossy. Pure given the
/// image details and page counts it's handed, so it's fully testable.
struct QuickActionPlanner {
    /// Whether something already exists at a URL — injectable for tests.
    var exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }

    func plan(
        _ request: QuickActionRequest,
        sources: [URL],
        imageInfo: [URL: ImageInfo] = [:],
        pageCounts: [URL: Int] = [:],
        textInfo: [URL: TextInfo] = [:],
        documents: Set<URL> = []
    ) -> QuickActionPlan {
        var claimed: Set<URL> = []
        switch request {
        case .resize(let target, _):
            let items = sources.map { url -> QuickActionPlanItem in
                guard let info = imageInfo[url] else { return unreadable(url) }
                guard let size = target.size(width: info.width, height: info.height) else {
                    return QuickActionPlanItem(source: url, detail: dimensions(info), outcome: .skip("Already that small"), note: nil)
                }
                let output = uniqueURL(suffixed(url, " (resized)"), claimed: &claimed)
                return QuickActionPlanItem(
                    source: url,
                    detail: "\(dimensions(info)) \u{2192} \(size.width) \u{00D7} \(size.height)",
                    outcome: .write(output),
                    note: nil
                )
            }
            let lossy = sources.contains { imageInfo[$0]?.format?.isLossy ?? false }
            return QuickActionPlan(
                items: items,
                combinedOutput: nil,
                warnings: lossy ? ["JPEG and HEIC images are re-compressed at the quality below."] : []
            )

        case .convert(let format, _):
            let items = sources.map { url -> QuickActionPlanItem in
                guard let info = imageInfo[url] else { return unreadable(url) }
                if info.format == format {
                    return QuickActionPlanItem(source: url, detail: dimensions(info), outcome: .skip("Already \(format.title)"), note: nil)
                }
                let output = uniqueURL(url.deletingPathExtension().appendingPathExtension(format.fileExtension), claimed: &claimed)
                let note = info.frameCount > 1 && !format.supportsMultipleImages ? "First frame only" : nil
                return QuickActionPlanItem(source: url, detail: dimensions(info), outcome: .write(output), note: note)
            }
            var warnings: [String] = []
            if format.isLossy { warnings.append("\(format.title) is lossy: some detail is lost at lower quality.") }
            if !format.supportsTransparency, sources.contains(where: { imageInfo[$0]?.hasAlpha ?? false }) {
                warnings.append("\(format.title) has no transparency: transparent areas become white.")
            }
            return QuickActionPlan(items: items, combinedOutput: nil, warnings: warnings)

        case .removeMetadata:
            let items = sources.map { url -> QuickActionPlanItem in
                guard let info = imageInfo[url] else { return unreadable(url) }
                guard !info.metadataKinds.isEmpty else {
                    return QuickActionPlanItem(source: url, detail: "No metadata", outcome: .skip("Nothing to remove"), note: nil)
                }
                let output = uniqueURL(suffixed(url, " (no metadata)"), claimed: &claimed)
                return QuickActionPlanItem(source: url, detail: info.metadataKinds.joined(separator: ", "), outcome: .write(output), note: nil)
            }
            return QuickActionPlan(
                items: items,
                combinedOutput: nil,
                warnings: ["Copies are made without location, EXIF, IPTC, and XMP details; orientation is kept. Formats that can't be copied as is are re-encoded at top quality."]
            )

        case .textToMarkdown, .markdownToHTML, .htmlToMarkdown:
            let ext = request.action == .markdownToHTML ? "html" : "md"
            let items = sources.map { url -> QuickActionPlanItem in
                guard let info = textInfo[url] else {
                    return QuickActionPlanItem(source: url, detail: "", outcome: .skip("Can't be read as text, or over 20 MB"), note: nil)
                }
                let output = uniqueURL(url.deletingPathExtension().appendingPathExtension(ext), claimed: &claimed)
                let detail = info.lineCount == 1 ? "1 line" : "\(info.lineCount) lines"
                return QuickActionPlanItem(source: url, detail: detail, outcome: .write(output), note: nil)
            }
            let warnings = request == .htmlToMarkdown
                ? ["Markdown keeps the text, headings, lists, links, images, and tables; layout, colors, and scripts are dropped."]
                : []
            return QuickActionPlan(items: items, combinedOutput: nil, warnings: warnings)

        case .convertToPDF:
            let items = sources.map { url -> QuickActionPlanItem in
                guard documents.contains(url) else { return unreadable(url) }
                let output = uniqueURL(url.deletingPathExtension().appendingPathExtension("pdf"), claimed: &claimed)
                return QuickActionPlanItem(source: url, detail: Self.documentKind(url), outcome: .write(output), note: nil)
            }
            return QuickActionPlan(items: items, combinedOutput: nil, warnings: [Self.documentWarning])

        case .combine(let name):
            let items = sources.map { url -> QuickActionPlanItem in
                if documents.contains(url) {
                    return QuickActionPlanItem(source: url, detail: "\(Self.documentKind(url)), converted to pages", outcome: .include, note: nil)
                }
                guard let pages = pageCounts[url] else {
                    return QuickActionPlanItem(source: url, detail: "", outcome: .skip("Can't be read, or password-protected"), note: nil)
                }
                return QuickActionPlanItem(source: url, detail: pages == 1 ? "1 page" : "\(pages) pages", outcome: .include, note: nil)
            }
            let trimmed = Self.fileName(from: name)
            let output = sources.first.flatMap { first -> URL? in
                guard let trimmed, items.contains(where: { !$0.isSkipped }) else { return nil }
                let folder = first.deletingLastPathComponent()
                return uniqueURL(folder.appendingPathComponent(trimmed).appendingPathExtension("pdf"), claimed: &claimed)
            }
            let hasDocuments = items.contains { documents.contains($0.source) }
            return QuickActionPlan(items: items, combinedOutput: output, warnings: hasDocuments ? [Self.documentWarning] : [], documents: documents)
        }
    }

    #if canImport(Darwin)
    static let documentWarning = "Documents are laid out the way TextEdit prints them: text, styles, lists, tables, and pictures come through; Word's page layout (headers and footers, columns, text boxes) may not."
    #else
    static let documentWarning = "Text files are printed in a plain monospaced font on A4 or Letter pages (by your locale); long lines wrap."
    #endif

    /// "Word document", "RTF document", "Text document".
    static func documentKind(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "doc", "docx", "wordml": return "Word document"
        case "rtf", "rtfd": return "RTF document"
        case "odt": return "OpenDocument text"
        default: return "Text document"
        }
    }

    /// `name` as a file name, or `nil` when it can't be one.
    static func fileName(from name: String) -> String? {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".pdf") { trimmed = String(trimmed.dropLast(4)) }
        guard !trimmed.isEmpty, !trimmed.hasPrefix("."), !trimmed.contains("/"), !trimmed.contains(":") else { return nil }
        return trimmed
    }

    // MARK: Helpers

    private func unreadable(_ url: URL) -> QuickActionPlanItem {
        QuickActionPlanItem(source: url, detail: "", outcome: .skip("Can't be read"), note: nil)
    }

    private func dimensions(_ info: ImageInfo) -> String {
        "\(info.width) \u{00D7} \(info.height)"
    }

    /// "photo.jpg" + " (resized)" → "photo (resized).jpg".
    private func suffixed(_ url: URL, _ suffix: String) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent + suffix
        let named = url.deletingLastPathComponent().appendingPathComponent(base)
        return ext.isEmpty ? named : named.appendingPathExtension(ext)
    }

    /// `url`, or "name (2).ext", "name (3).ext", … — whichever is free on
    /// disk and not already taken by another output of this plan.
    private func uniqueURL(_ url: URL, claimed: inout Set<URL>) -> URL {
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var candidate = url
        var counter = 2
        while exists(candidate) || claimed.contains(candidate.standardizedFileURL) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            counter += 1
        }
        claimed.insert(candidate.standardizedFileURL)
        return candidate
    }
}
