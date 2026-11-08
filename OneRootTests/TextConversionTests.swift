import XCTest
@testable import OneRoot

final class TextConversionServiceTests: XCTestCase {
    private let service = TextConversionService()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Plain text

    func testPlainTextKeepsParagraphsAndLineBreaks() {
        let markdown = service.markdown(fromPlainText: "Dear Sam,\r\nSee you soon.\n\n\n\nBye", keepLineBreaks: true, escapeSymbols: false)
        XCTAssertEqual(markdown, "Dear Sam,  \nSee you soon.\n\nBye\n")
    }

    func testPlainTextCanJoinLines() {
        XCTAssertEqual(service.markdown(fromPlainText: "one\ntwo", keepLineBreaks: false, escapeSymbols: false), "one\ntwo\n")
    }

    func testMarkdownLookingTextStaysMarkdownUnlessEscaped() {
        let text = "# Groceries\n- milk\n*urgent* 2. eggs\n    indented"
        XCTAssertEqual(service.markdown(fromPlainText: text, keepLineBreaks: false, escapeSymbols: false), text + "\n")
        let escaped = service.markdown(fromPlainText: text, keepLineBreaks: false, escapeSymbols: true)
        XCTAssertEqual(escaped, "\\# Groceries\n\\- milk\n\\*urgent\\* 2. eggs\n&nbsp;&nbsp;&nbsp;&nbsp;indented\n")
    }

    func testReadsOlderEncodingsAndRejectsBinary() throws {
        let latin = folder.appendingPathComponent("old.txt")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: latin) // "café" in Windows-1252
        XCTAssertEqual(try service.convertedText(of: latin, for: .textToMarkdown(keepLineBreaks: true, escapeSymbols: false)), "café\n")
        let binary = folder.appendingPathComponent("blob.txt")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: binary)
        XCTAssertThrowsError(try service.info(for: binary))
    }

    func testConvertWritesBesideAndNeverReplaces() throws {
        let notes = try write("notes.txt", "hello")
        try "keep".write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let written = try service.convert(notes, for: .textToMarkdown(keepLineBreaks: true, escapeSymbols: false), output: folder.appendingPathComponent("notes.md"))
        XCTAssertEqual(written.lastPathComponent, "notes (2).md")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("notes.md"), encoding: .utf8), "keep")
        XCTAssertEqual(try String(contentsOf: written, encoding: .utf8), "hello\n")
    }

    func testInfoCountsLines() throws {
        XCTAssertEqual(try service.info(for: try write("a.txt", "1\n2\n3")).lineCount, 3)
    }

    func testHTMLFileWithoutCharsetKeepsAccents() throws {
        let page = try write("page.html", "<html><body><p>Château</p></body></html>")
        XCTAssertEqual(try service.convertedText(of: page, for: .htmlToMarkdown), "Château\n")
    }

    // MARK: Markdown → HTML

    func testMarkdownToHTMLDocumentUsesTheFirstHeadingAsTitle() throws {
        let md = try write("Read Me.md", "# Project & Plans\n\nHello.")
        let html = try service.convertedText(of: md, for: .markdownToHTML(styled: true))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>Project &amp; Plans</title>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertFalse(try service.convertedText(of: md, for: .markdownToHTML(styled: false)).contains("<style>"))
    }
}

final class MarkdownHTMLRendererTests: XCTestCase {
    private let renderer = MarkdownHTMLRenderer()

    func testBlocksAndInlines() throws {
        let html = try renderer.body(fromMarkdown: """
        # Title *here*

        Some **bold**, `a < b`, ~~gone~~ and a [link](https://x.com).
        Next line\\
        broken.

        > quoted

        ---
        """)
        XCTAssertEqual(html, """
        <h1>Title <em>here</em></h1>
        <p>Some <strong>bold</strong>, <code>a &lt; b</code>, <del>gone</del> and a <a href="https://x.com">link</a>.
        Next line<br>
        broken.</p>
        <blockquote>
        <p>quoted</p>
        </blockquote>
        <hr>

        """)
    }

    func testNestedListsAreTightAndOrderedListsKeepTheirStart() throws {
        let html = try renderer.body(fromMarkdown: "- a\n- b\n  1. c\n  2. d")
        XCTAssertEqual(html, "<ul>\n<li>a</li>\n<li>b<ol>\n<li>c</li>\n<li>d</li>\n</ol>\n</li>\n</ul>\n")
        XCTAssertEqual(try renderer.body(fromMarkdown: "3. c\n4. d"), "<ol start=\"3\">\n<li>c</li>\n<li>d</li>\n</ol>\n")
    }

    func testCodeBlocksTablesAndImages() throws {
        let html = try renderer.body(fromMarkdown: """
        ```swift
        let x = "<y>"
        ```

        | A | B |
        |---|:-:|
        | 1 | 2 |

        ![a cat](cat.png)
        """)
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">let x = &quot;&lt;y&gt;&quot;\n</code></pre>"))
        XCTAssertTrue(html.contains("<thead>\n<tr><th>A</th><th style=\"text-align: center\">B</th></tr>\n</thead>"))
        XCTAssertTrue(html.contains("<tbody>\n<tr><td>1</td><td style=\"text-align: center\">2</td></tr>\n</tbody>"))
        XCTAssertTrue(html.contains("<img src=\"cat.png\" alt=\"a cat\">"))
    }

    /// Foundation's parser drops emphasis inside link text; the link
    /// itself must still come out whole.
    func testFormattedLinkStaysOneLink() throws {
        let html = try renderer.body(fromMarkdown: "[go **now** please](https://a.b)")
        XCTAssertEqual(html, "<p><a href=\"https://a.b\">go now please</a></p>\n")
    }
}

final class HTMLMarkdownConverterTests: XCTestCase {
    private let converter = HTMLMarkdownConverter()

    private func markdown(_ html: String) throws -> String {
        try converter.markdown(fromHTML: html)
    }

    func testHeadingsParagraphsAndInlines() throws {
        let md = try markdown("""
        <html><head><title>T</title><style>p{color:red}</style><script>alert(1)</script></head>
        <body><h2>Hi <em>there</em></h2>
        <p>Some  <b>bold </b>&amp; <a href="https://a.b">a link</a><br>next   line</p>
        <p>Price *not* bold, <code>x_y</code></p></body></html>
        """)
        XCTAssertEqual(md, """
        ## Hi *there*

        Some **bold** & [a link](https://a.b)\\
        next line

        Price \\*not\\* bold, `x_y`

        """)
    }

    func testListsNestAndNumber() throws {
        let md = try markdown("<ul><li>one<ul><li>deep</li></ul></li><li>two</li></ul><ol start=\"4\"><li>four</li><li>five</li></ol>")
        XCTAssertEqual(md, "- one\n  - deep\n- two\n\n4. four\n5. five\n")
    }

    func testCodeQuotesTablesImages() throws {
        let md = try markdown("""
        <pre><code class="language-python">x = 1
        y = 2</code></pre>
        <blockquote><p>wise</p><p>words</p></blockquote>
        <table><tr><th>A</th><th>B|C</th></tr><tr><td>1</td><td>2</td></tr></table>
        <img src="my pic.png" alt="pic"><hr>
        """)
        XCTAssertEqual(md, """
        ```python
        x = 1
        y = 2
        ```

        > wise
        >
        > words

        | A | B\\|C |
        | --- | --- |
        | 1 | 2 |

        ![pic](my%20pic.png)

        ---

        """)
    }

    func testParagraphsThatLookLikeMarkdownAreEscaped() throws {
        XCTAssertEqual(try markdown("<p># not a heading</p><p>1. not a list</p>"), "\\# not a heading\n\n1\\. not a list\n")
    }

    func testKeepsAccentsWithoutACharsetDeclaration() throws {
        XCTAssertEqual(try markdown("<p>Château — café ✓</p>"), "Château — café ✓\n")
    }

    func testForgivesBrokenHTML() throws {
        XCTAssertEqual(try markdown("<p>unclosed<p>second <b>bold"), "unclosed\n\nsecond **bold**\n")
    }
}
