import Foundation
#if !canImport(Darwin)
import Markdown // Linux: swift-markdown
#endif

/// Finds Help topics for what's typed in the Help window's search field.
/// Every word must appear somewhere in a topic (its title, keywords, or
/// text, ignoring case and accents and Markdown markup); topics whose
/// title matches come first, then ones whose keywords do, then the rest,
/// each in their usual order.
struct HelpSearch {
    struct Result: Equatable {
        let topicID: HelpTopicID
        /// A short excerpt of the text around the first match, or nil when
        /// only the title or keywords matched.
        let snippet: String?
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The words of a query, without empty ones.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Nothing for an empty query — the caller shows every topic instead.
    static func results(for query: String, in topics: [HelpTopic]) -> [Result] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }

        var scored: [(score: Int, order: Int, result: Result)] = []
        for (order, topic) in topics.enumerated() {
            let paragraphs = topic.blocks.flatMap(\.texts).map(plainText)
            let haystacks = [topic.title] + topic.keywords + paragraphs
            guard terms.allSatisfy({ term in haystacks.contains { contains($0, term) } }) else { continue }

            let score: Int
            if terms.contains(where: { contains(topic.title, $0) }) {
                score = 2
            } else if terms.contains(where: { term in topic.keywords.contains { contains($0, term) } }) {
                score = 1
            } else {
                score = 0
            }
            let snippet = paragraphs.lazy.compactMap { snippet(of: $0, around: terms) }.first
            scored.append((score, order, Result(topicID: topic.id, snippet: snippet)))
        }
        return scored
            .sorted { ($0.score, -$0.order) > ($1.score, -$1.order) }
            .map(\.result)
    }

    /// The text of inline Markdown without its markup: `**Inspector**` →
    /// "Inspector", `[ICU](https://…)` → "ICU".
    static func plainText(_ markdown: String) -> String {
        #if canImport(Darwin)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else { return markdown }
        return String(attributed.characters)
        #else
        let blocks = Document(parsing: markdown).children.compactMap { ($0 as? InlineContainer)?.plainText }
        return blocks.isEmpty ? markdown : blocks.joined(separator: "\n")
        #endif
    }

    /// About `radius` characters either side of the first term found in
    /// `text`, with "…" where it was cut.
    static func snippet(of text: String, around terms: [String], radius: Int = 60) -> String? {
        guard let match = terms.lazy.compactMap({ text.range(of: $0, options: options) }).first else { return nil }
        var start = text.index(match.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(match.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        // Cut at word boundaries so the snippet doesn't start mid-word.
        if start > text.startIndex, let space = text[start..<match.lowerBound].firstIndex(of: " ") {
            start = text.index(after: space)
        }
        if end < text.endIndex, let space = text[match.upperBound..<end].lastIndex(of: " ") {
            end = space
        }
        let excerpt = text[start..<end].trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "") + excerpt + (end < text.endIndex ? "…" : "")
    }

    private static func contains(_ text: String, _ term: String) -> Bool {
        text.range(of: term, options: options) != nil
    }
}
