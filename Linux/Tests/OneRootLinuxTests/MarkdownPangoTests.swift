import XCTest
@testable import OneRootLinux

final class MarkdownPangoTests: XCTestCase {
    func testHeadingsAndEmphasis() {
        let markup = MarkdownPango.markup(from: "# Title\n\nSome **bold**, *italic* and `code`.")
        XCTAssertTrue(markup.contains("<span size=\"xx-large\" weight=\"bold\">Title</span>"))
        XCTAssertTrue(markup.contains("<b>bold</b>"))
        XCTAssertTrue(markup.contains("<i>italic</i>"))
        XCTAssertTrue(markup.contains("<tt>code</tt>"))
    }

    func testListsAndLinks() {
        let markup = MarkdownPango.markup(from: "- one\n- two\n\n1. first\n\n[site](https://example.com)")
        XCTAssertTrue(markup.contains("\u{2022} one"))
        XCTAssertTrue(markup.contains("1. first"))
        XCTAssertTrue(markup.contains("<a href=\"https://example.com\">site</a>"))
    }

    func testCodeBlocksAreVerbatimAndEscaped() {
        let markup = MarkdownPango.markup(from: "```\nlet a = 1 < 2 && **x**\n```")
        XCTAssertEqual(markup, "<tt>let a = 1 &lt; 2 &amp;&amp; **x**</tt>")
    }

    func testMarkupSpecialCharactersAreEscapedInText() {
        XCTAssertEqual(MarkdownPango.markup(from: "a < b & c > d"), "a &lt; b &amp; c &gt; d")
    }

    func testUnclosedMarkersStayPlain() {
        XCTAssertEqual(MarkdownPango.markup(from: "a **b and `c"), "a **b and `c")
    }
}
