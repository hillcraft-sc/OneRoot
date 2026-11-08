import XCTest
@testable import OneRoot

final class HelpSearchTests: XCTestCase {
    private let topics = [
        HelpTopic(id: .inspector, title: "The Inspector", symbolName: "sidebar.right", section: .browsing,
                  keywords: ["Properties"],
                  blocks: [.paragraph("Shows a **preview** of the selection and its details.")]),
        HelpTopic(id: .fileOperations, title: "Copying, Moving & Renaming", symbolName: "doc.on.doc", section: .files,
                  blocks: [.paragraph("Select items and press **Return** to rename, or use the [Inspector](https://example.com).")]),
        HelpTopic(id: .themes, title: "Themes", symbolName: "paintpalette", section: .customizing,
                  blocks: [.bullets(["Catppuccin Frapp\u{00E9}", "Nord"])]),
    ]

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(HelpSearch.results(for: "", in: topics).isEmpty)
        XCTAssertTrue(HelpSearch.results(for: "   ", in: topics).isEmpty)
    }

    func testTitleMatchesComeBeforeTextMatches() {
        let ids = HelpSearch.results(for: "inspector", in: topics).map(\.topicID)
        XCTAssertEqual(ids, [.inspector, .fileOperations])
    }

    func testKeywordsAreSearched() {
        let results = HelpSearch.results(for: "properties", in: topics)
        XCTAssertEqual(results.map(\.topicID), [.inspector])
        XCTAssertNil(results.first?.snippet, "Only a keyword matched, so there's no text to excerpt")
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(HelpSearch.results(for: "rename return", in: topics).map(\.topicID), [.fileOperations])
        XCTAssertTrue(HelpSearch.results(for: "rename nord", in: topics).isEmpty)
    }

    func testIgnoresCaseAndAccents() {
        XCTAssertEqual(HelpSearch.results(for: "FRAPPE", in: topics).map(\.topicID), [.themes])
    }

    func testMarkdownMarkupIsNotSearchedOrShown() {
        XCTAssertTrue(HelpSearch.results(for: "example.com", in: topics).isEmpty)
        XCTAssertTrue(HelpSearch.results(for: "**", in: topics).isEmpty)
        let snippet = HelpSearch.results(for: "preview", in: topics).first?.snippet
        XCTAssertEqual(snippet, "Shows a preview of the selection and its details.")
    }

    func testSnippetIsCutAtWordsAroundTheMatch() throws {
        let text = String(repeating: "lorem ipsum ", count: 20) + "needle" + String(repeating: " dolor sit", count: 20)
        let snippet = try XCTUnwrap(HelpSearch.snippet(of: text, around: ["needle"], radius: 20))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertTrue(snippet.contains("needle"))
        let words = snippet.trimmingCharacters(in: CharacterSet(charactersIn: "…")).split(separator: " ")
        XCTAssertTrue(words.allSatisfy { ["lorem", "ipsum", "needle", "dolor", "sit"].contains(String($0)) })
    }

    // MARK: - The real content

    func testEveryTopicIDHasExactlyOneTopic() {
        let ids = HelpContent.topics.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(HelpTopicID.allCases))
    }

    func testSeeAlsoNeverPointsToItself() {
        for topic in HelpContent.topics {
            XCTAssertFalse(topic.seeAlso.contains(topic.id), topic.title)
        }
    }

    func testWindowsTermsFindTheirOneRootCounterparts() {
        let content = HelpContent.topics
        XCTAssertTrue(HelpSearch.results(for: "Properties", in: content).map(\.topicID).contains(.inspector))
        XCTAssertTrue(HelpSearch.results(for: "Recycle Bin", in: content).map(\.topicID).contains(.comingFromWindows))
        XCTAssertTrue(HelpSearch.results(for: "map network drive", in: content).map(\.topicID).contains(.networkShares))
    }

    func testKeyboardShortcutsTopicListsEverySection() {
        let topic = HelpContent.topic(.shortcuts)
        let headings = topic?.blocks.compactMap { block -> String? in
            if case .heading(let title) = block { return title }
            return nil
        }
        XCTAssertEqual(headings, KeyboardShortcutReference.sections.map(\.title))
    }
}
