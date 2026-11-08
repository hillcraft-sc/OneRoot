import Foundation
#if canImport(FoundationXML)
import FoundationXML // Linux: XMLDocument and friends live here
#endif

enum HTMLMarkdownError: LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "“\(name)” couldn't be read as HTML."
        }
    }
}

/// HTML to Markdown: Foundation's forgiving HTML parser (`XMLDocument`
/// with tidying) builds the tree, and this writes out what Markdown can
/// say — headings, paragraphs, emphasis, links, images, lists, quotes,
/// code, tables. Layout, styling, scripts, and forms are dropped.
struct HTMLMarkdownConverter {
    /// Takes text already decoded: given bytes, the parser drops every
    /// non-ASCII character when the page doesn't declare its encoding.
    func markdown(fromHTML html: String) throws -> String {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement()
        else { throw HTMLMarkdownError.unreadable("HTML") }
        let body = root.elements(forName: "body").first ?? root
        let blocks = self.blocks(in: body)
        var markdown = blocks.joined(separator: "\n\n")
        while markdown.contains("\n\n\n") {
            markdown = markdown.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown.isEmpty ? "" : markdown + "\n"
    }

    // MARK: Blocks

    private static let skipped: Set<String> = ["head", "script", "style", "noscript", "template", "title", "meta", "link", "form", "input", "button", "select", "textarea", "iframe", "svg", "canvas", "nav"]
    private static let blockNames: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "center", "dd", "details", "dialog", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "html",
        "li", "main", "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    /// `element`'s children as Markdown blocks; loose text and inline
    /// elements between blocks become paragraphs.
    private func blocks(in element: XMLElement) -> [String] {
        taggedBlocks(in: element).map(\.text)
    }

    /// The blocks, each marked whether it's a list — a list item's text and
    /// its nested list sit on consecutive lines.
    private func taggedBlocks(in element: XMLElement) -> [(text: String, isList: Bool)] {
        var blocks: [(text: String, isList: Bool)] = []
        var pending: [XMLNode] = []
        func flush() {
            let paragraph = Self.escapeLineStart(inline(pending).trimmingCharacters(in: .whitespacesAndNewlines))
            if !paragraph.isEmpty { blocks.append((paragraph, false)) }
            pending = []
        }
        for child in element.children ?? [] {
            if let child = child as? XMLElement, let name = child.localName?.lowercased() {
                if Self.skipped.contains(name) { continue }
                if Self.blockNames.contains(name) {
                    flush()
                    let isList = name == "ul" || name == "ol"
                    blocks.append(contentsOf: block(child, name: name).map { ($0, isList) })
                    continue
                }
            }
            pending.append(child)
        }
        flush()
        return blocks
    }

    private func block(_ element: XMLElement, name: String) -> [String] {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 1
            let text = inline(element.children ?? []).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
        case "p", "dt", "dd", "summary", "figcaption":
            let text = Self.escapeLineStart(inline(element.children ?? []).trimmingCharacters(in: .whitespacesAndNewlines))
            return text.isEmpty ? [] : [text]
        case "hr":
            return ["---"]
        case "pre":
            return [codeBlock(element)]
        case "blockquote":
            let inner = blocks(in: element).joined(separator: "\n\n")
            guard !inner.isEmpty else { return [] }
            return [inner.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")]
        case "ul", "ol":
            return [list(element, ordered: name == "ol")]
        case "table":
            return table(element).map { [$0] } ?? []
        default:
            return blocks(in: element)
        }
    }

    private func codeBlock(_ pre: XMLElement) -> String {
        let code = pre.elements(forName: "code").first
        let language = (code?.attribute(forName: "class")?.stringValue ?? "")
            .split(separator: " ")
            .first { $0.hasPrefix("language-") }
            .map { String($0.dropFirst("language-".count)) } ?? ""
        var text = (code ?? pre).stringValue ?? ""
        // The parser keeps the line break after <pre>; HTML ignores it.
        while text.hasPrefix("\n") { text.removeFirst() }
        while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
        let fence = text.contains("```") ? "~~~~" : "```"
        return "\(fence)\(language)\n\(text)\n\(fence)"
    }

    private func list(_ element: XMLElement, ordered: Bool) -> String {
        var number = Int(element.attribute(forName: "start")?.stringValue ?? "") ?? 1
        var items: [String] = []
        for item in element.elements(forName: "li") {
            let marker = ordered ? "\(number). " : "- "
            number += 1
            let parts = taggedBlocks(in: item)
            // Tight unless the item has more than one paragraph.
            let tight = parts.filter { !$0.isList }.count <= 1
            let content = parts.map(\.text).joined(separator: tight ? "\n" : "\n\n")
            let indent = String(repeating: " ", count: marker.count)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            let body = lines.enumerated().map { index, line in
                index == 0 ? marker + line : (line.isEmpty ? "" : indent + line)
            }.joined(separator: "\n")
            items.append(body.isEmpty ? marker.trimmingCharacters(in: .whitespaces) : body)
        }
        // Items with several paragraphs need a blank line between items.
        let loose = items.contains { $0.contains("\n\n") }
        return items.joined(separator: loose ? "\n\n" : "\n")
    }

    private func table(_ table: XMLElement) -> String? {
        var rows: [XMLElement] = []
        func collectRows(_ element: XMLElement) {
            for child in element.children ?? [] {
                guard let child = child as? XMLElement, let name = child.localName?.lowercased() else { continue }
                if name == "tr" { rows.append(child) } else if ["thead", "tbody", "tfoot"].contains(name) { collectRows(child) }
            }
        }
        collectRows(table)
        let cells: [[String]] = rows.map { row in
            (row.children ?? []).compactMap { $0 as? XMLElement }
                .filter { ["td", "th"].contains($0.localName?.lowercased() ?? "") }
                .map {
                    inline($0.children ?? [])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "|", with: "\\|")
                }
        }.filter { !$0.isEmpty }
        guard let header = cells.first else { return nil }
        let width = cells.map(\.count).max() ?? header.count
        func line(_ row: [String]) -> String {
            "| " + (row + Array(repeating: "", count: width - row.count)).joined(separator: " | ") + " |"
        }
        var lines = [line(header), "|" + Array(repeating: " --- |", count: width).joined()]
        lines += cells.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    // MARK: Inline

    private func inline(_ nodes: [XMLNode]) -> String {
        var text = ""
        for node in nodes {
            text += inline(node)
        }
        return text
    }

    private func inline(_ node: XMLNode) -> String {
        guard let element = node as? XMLElement else {
            guard node.kind == .text else { return "" }
            return Self.escape(Self.collapseWhitespace(node.stringValue ?? ""))
        }
        let name = element.localName?.lowercased() ?? ""
        if Self.skipped.contains(name) { return "" }
        let content = inline(element.children ?? [])
        switch name {
        case "br":
            return "\\\n"
        case "strong", "b":
            return Self.wrap(content, "**")
        case "em", "i":
            return Self.wrap(content, "*")
        case "del", "s", "strike":
            return Self.wrap(content, "~~")
        case "code", "kbd", "samp", "tt":
            let raw = Self.collapseWhitespace(element.stringValue ?? "")
            guard !raw.isEmpty else { return "" }
            let fence = raw.contains("`") ? "``" : "`"
            return "\(fence)\(raw)\(fence)"
        case "a":
            let label = content.trimmingCharacters(in: .whitespaces)
            guard let href = element.attribute(forName: "href")?.stringValue, !href.isEmpty, !href.hasPrefix("javascript:") else {
                return content
            }
            return "[\(label.isEmpty ? href : label)](\(Self.destination(href)))"
        case "img":
            guard let src = element.attribute(forName: "src")?.stringValue, !src.isEmpty else { return "" }
            let alt = Self.escape(element.attribute(forName: "alt")?.stringValue ?? "")
            return "![\(alt)](\(Self.destination(src)))"
        default:
            // A block element met inside inline content (a <div> in a
            // link): keep its words, with a space so they don't run together.
            return Self.blockNames.contains(name) ? " \(content) " : content
        }
    }

    // MARK: Text

    /// `**word**`, keeping the spaces around it outside the markers (so
    /// "**bold **" doesn't stop being bold).
    private static func wrap(_ content: String, _ marker: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return content }
        let leading = content.hasPrefix(" ") ? " " : ""
        let trailing = content.hasSuffix(" ") ? " " : ""
        return leading + marker + trimmed + marker + trailing
    }

    private static func destination(_ url: String) -> String {
        url.contains(" ") || url.contains("(") || url.contains(")") ? "<\(url)>" : url
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Characters Markdown would read as formatting, backslash-escaped.
    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// A paragraph starting "# ", "- ", "1. ", … would turn into a heading
    /// or list; escape its first character.
    static func escapeLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#>+-=".contains(first) { return "\\" + line }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(".") || line.dropFirst(digits.count).hasPrefix(")") {
            return digits + "\\" + line.dropFirst(digits.count)
        }
        return line
    }
}
