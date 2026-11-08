import Foundation
#if !canImport(Darwin)
import Markdown // Linux: swift-markdown (Foundation's Markdown parser is Apple-only)
#endif

/// Markdown to HTML, using Foundation's own Markdown parser (GitHub-style:
/// tables, strikethrough, fenced code) and rendering its block structure
/// as HTML. Raw HTML in the Markdown passes through, as Markdown intends.
struct MarkdownHTMLRenderer {
    /// The HTML for `markdown`'s body — no `<html>`/`<head>`.
    func body(fromMarkdown markdown: String) throws -> String {
        #if canImport(Darwin)
        let parsed = try AttributedString(
            markdown: markdown,
            options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        )
        let root = Block(kind: nil, identity: -1)
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let segment = Inline(
                text: text,
                intent: run.inlinePresentationIntent ?? [],
                link: run.link,
                imageURL: run.imageURL
            )
            // Outermost first: the document's nesting, top down.
            let path = (run.presentationIntent?.components ?? []).reversed()
            var block = root
            for component in path {
                if let last = block.children.last, case .block(let child) = last, child.identity == component.identity {
                    block = child
                } else {
                    let child = Block(kind: component.kind, identity: component.identity)
                    block.children.append(.block(child))
                    block = child
                }
            }
            block.children.append(.inline(segment))
        }
        return render(children: root.children, tightList: false)
        #else
        return HTMLFormatter.format(markdown)
        #endif
    }

    /// A whole page: `title`, UTF-8, and (with `styled`) a little CSS that
    /// follows light and dark mode.
    func document(fromMarkdown markdown: String, title: String, styled: Bool) throws -> String {
        let body = try body(fromMarkdown: markdown)
        let style = styled ? "\n<style>\n\(Self.css)\n</style>" : ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Self.escape(title))</title>\(style)
        </head>
        <body>
        \(body)</body>
        </html>

        """
    }

    #if canImport(Darwin)
    // MARK: Tree

    private final class Block {
        let kind: PresentationIntent.Kind?
        let identity: Int
        var children: [Node] = []

        init(kind: PresentationIntent.Kind?, identity: Int) {
            self.kind = kind
            self.identity = identity
        }
    }

    private struct Inline {
        let text: String
        let intent: InlinePresentationIntent
        let link: URL?
        let imageURL: URL?
    }

    private enum Node {
        case block(Block)
        case inline(Inline)
    }

    // MARK: Rendering

    private func render(children: [Node], tightList: Bool) -> String {
        var html = ""
        var inlines: [Inline] = []
        func flushInlines() {
            guard !inlines.isEmpty else { return }
            html += renderInlines(inlines)
            inlines = []
        }
        for child in children {
            switch child {
            case .inline(let inline):
                inlines.append(inline)
            case .block(let block):
                flushInlines()
                html += render(block, tightList: tightList)
            }
        }
        flushInlines()
        return html
    }

    private func render(_ block: Block, tightList: Bool) -> String {
        guard let kind = block.kind else { return render(children: block.children, tightList: false) }
        switch kind {
        case .paragraph:
            let content = render(children: block.children, tightList: false)
            return tightList ? content : "<p>\(content)</p>\n"
        case .header(let level):
            let level = min(max(level, 1), 6)
            return "<h\(level)>\(render(children: block.children, tightList: false))</h\(level)>\n"
        case .orderedList:
            let start = block.children.compactMap { node -> Int? in
                if case .block(let item) = node, case .listItem(let ordinal)? = item.kind { return ordinal }
                return nil
            }.first ?? 1
            let attribute = start == 1 ? "" : " start=\"\(start)\""
            return "<ol\(attribute)>\n\(render(children: block.children, tightList: false))</ol>\n"
        case .unorderedList:
            return "<ul>\n\(render(children: block.children, tightList: false))</ul>\n"
        case .listItem:
            // One paragraph (plus any nested lists): a tight item, no <p>.
            let paragraphs = block.children.filter {
                if case .block(let child) = $0, case .paragraph? = child.kind { return true }
                return false
            }.count
            return "<li>\(render(children: block.children, tightList: paragraphs <= 1))</li>\n"
        case .blockQuote:
            return "<blockquote>\n\(render(children: block.children, tightList: false))</blockquote>\n"
        case .codeBlock(let language):
            let code = block.children.compactMap { node -> String? in
                if case .inline(let inline) = node { return inline.text }
                return nil
            }.joined()
            let attribute = language.flatMap { $0.isEmpty ? nil : " class=\"language-\(Self.escape($0))\"" } ?? ""
            return "<pre><code\(attribute)>\(Self.escape(code))</code></pre>\n"
        case .thematicBreak:
            return "<hr>\n"
        case .table(let columns):
            return renderTable(block, columns: columns)
        case .tableHeaderRow, .tableRow, .tableCell:
            return render(children: block.children, tightList: false)
        @unknown default:
            return render(children: block.children, tightList: false)
        }
    }

    private func renderTable(_ table: Block, columns: [PresentationIntent.TableColumn]) -> String {
        var head = ""
        var rows = ""
        for node in table.children {
            guard case .block(let row) = node else { continue }
            let isHeader: Bool
            if case .tableHeaderRow? = row.kind { isHeader = true } else { isHeader = false }
            var cells = ""
            for cellNode in row.children {
                guard case .block(let cell) = cellNode, case .tableCell(let column)? = cell.kind else { continue }
                let tag = isHeader ? "th" : "td"
                var style = ""
                if columns.indices.contains(column) {
                    switch columns[column].alignment {
                    case .center: style = " style=\"text-align: center\""
                    case .right: style = " style=\"text-align: right\""
                    default: break
                    }
                }
                cells += "<\(tag)\(style)>\(render(children: cell.children, tightList: false))</\(tag)>"
            }
            if isHeader { head += "<tr>\(cells)</tr>\n" } else { rows += "<tr>\(cells)</tr>\n" }
        }
        var html = "<table>\n"
        if !head.isEmpty { html += "<thead>\n\(head)</thead>\n" }
        if !rows.isEmpty { html += "<tbody>\n\(rows)</tbody>\n" }
        return html + "</table>\n"
    }

    /// Runs in a row that share a link become one `<a>`.
    private func renderInlines(_ inlines: [Inline]) -> String {
        var html = ""
        var index = 0
        while index < inlines.count {
            let inline = inlines[index]
            if let imageURL = inline.imageURL {
                var alt = ""
                while index < inlines.count, inlines[index].imageURL == imageURL {
                    alt += inlines[index].text
                    index += 1
                }
                html += "<img src=\"\(Self.escape(imageURL.absoluteString))\" alt=\"\(Self.escape(alt))\">"
            } else if let link = inline.link {
                var content = ""
                while index < inlines.count, inlines[index].link == link, inlines[index].imageURL == nil {
                    content += renderInline(inlines[index])
                    index += 1
                }
                html += "<a href=\"\(Self.escape(link.absoluteString))\">\(content)</a>"
            } else {
                html += renderInline(inline)
                index += 1
            }
        }
        return html
    }

    private func renderInline(_ inline: Inline) -> String {
        let intent = inline.intent
        if intent.contains(.inlineHTML) || intent.contains(.blockHTML) { return inline.text }
        if intent.contains(.lineBreak) { return "<br>\n" }
        if intent.contains(.softBreak) { return "\n" }
        var html = Self.escape(inline.text)
        if intent.contains(.code) { html = "<code>\(html)</code>" }
        if intent.contains(.strikethrough) { html = "<del>\(html)</del>" }
        if intent.contains(.emphasized) { html = "<em>\(html)</em>" }
        if intent.contains(.stronglyEmphasized) { html = "<strong>\(html)</strong>" }
        return html
    }

    #endif

    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body { font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; max-width: 46em; margin: 2em auto; padding: 0 1.25em; }
    pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
    pre { padding: 0.8em 1em; overflow-x: auto; border-radius: 6px; background: rgba(127, 127, 127, 0.12); }
    code { padding: 0.1em 0.3em; border-radius: 4px; background: rgba(127, 127, 127, 0.12); }
    pre code { padding: 0; background: none; }
    blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid rgba(127, 127, 127, 0.4); color: rgba(127, 127, 127, 1); }
    table { border-collapse: collapse; }
    th, td { padding: 0.35em 0.75em; border: 1px solid rgba(127, 127, 127, 0.35); }
    img { max-width: 100%; }
    hr { border: none; border-top: 1px solid rgba(127, 127, 127, 0.35); }
    """
}
