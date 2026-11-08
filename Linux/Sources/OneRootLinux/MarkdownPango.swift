import Foundation

/// A Markdown file as Pango markup for a label: headings, bold, italic,
/// inline code, links, bullet and numbered lists, quotes and code blocks.
/// A small reader for previews, not a full CommonMark: anything it doesn't
/// know stays as plain text. Pure, so it is tested.
enum MarkdownPango {
    static func markup(from markdown: String) -> String {
        var out: [String] = []
        var inFence = false
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence {
                out.append("<tt>\(escape(line))</tt>")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { out.append(""); continue }
            if let (level, text) = heading(trimmed) {
                let size = ["xx-large", "x-large", "large", "medium", "medium", "small"][min(level, 6) - 1]
                out.append("<span size=\"\(size)\" weight=\"bold\">\(inline(text))</span>")
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                out.append("<i>\u{2502} \(inline(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))</i>")
            } else if let bullet = bulletText(trimmed) {
                let indent = String(repeating: "  ", count: (line.prefix { $0 == " " }.count) / 2)
                out.append("\(indent)\u{2022} \(inline(bullet))")
            } else if let (number, text) = numbered(trimmed) {
                out.append("\(number). \(inline(text))")
            } else if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && trimmed.count >= 3 {
                out.append("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")
            } else {
                out.append(inline(trimmed))
            }
        }
        // Blank lines collapse to one.
        var collapsed: [String] = []
        for line in out where !(line.isEmpty && collapsed.last?.isEmpty == true) { collapsed.append(line) }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(2)) }
        return nil
    }

    private static func numbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (String(digits), String(line.dropFirst(digits.count + 2)))
    }

    /// Bold, italic, code and links inside a line; everything else escaped.
    static func inline(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        func take(until marker: String, from start: String.Index) -> (String, String.Index)? {
            guard let range = text.range(of: marker, range: start..<text.endIndex), range.lowerBound > start else { return nil }
            return (String(text[start..<range.lowerBound]), range.upperBound)
        }
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("`"), let (code, next) = take(until: "`", from: text.index(after: index)) {
                result += "<tt>\(escape(code))</tt>"
                index = next
            } else if rest.hasPrefix("**"), let (bold, next) = take(until: "**", from: text.index(index, offsetBy: 2)) {
                result += "<b>\(inline(bold))</b>"
                index = next
            } else if rest.hasPrefix("*") || rest.hasPrefix("_"), !rest.hasPrefix("**"),
                      let marker = rest.first.map(String.init),
                      let (italic, next) = take(until: marker, from: text.index(after: index)), !italic.hasPrefix(" ") {
                result += "<i>\(inline(italic))</i>"
                index = next
            } else if rest.hasPrefix("["), let (label, afterLabel) = take(until: "](", from: text.index(after: index)),
                      let (url, next) = take(until: ")", from: afterLabel) {
                result += "<a href=\"\(escape(url).replacingOccurrences(of: "\"", with: "&quot;"))\">\(inline(label))</a>"
                index = next
            } else {
                result += escape(String(text[index]))
                index = text.index(after: index)
            }
        }
        return result
    }
}
