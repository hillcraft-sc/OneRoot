import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class HelpContentTests: XCTestCase {
    func testMarkupConvertsBoldAndCodeAndEscapes() {
        XCTAssertEqual(HelpMarkup.pango("a **b** `c` & <d>"), "a <b>b</b> <tt>c</tt> &amp; &lt;d&gt;")
    }

    func testMarkupClosesUnbalancedTags() {
        XCTAssertEqual(HelpMarkup.pango("**open"), "<b>open</b>")
    }

    func testTopicsAreUniqueAndLinksResolve() {
        let ids = LinuxHelpContent.topics.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for topic in LinuxHelpContent.topics {
            XCTAssertFalse(topic.blocks.isEmpty, topic.title)
            for related in topic.seeAlso {
                XCTAssertNotNil(LinuxHelpContent.topic(related), "\(topic.title) links to a missing topic")
            }
        }
        XCTAssertNotNil(LinuxHelpContent.topic(.gettingStarted))
        XCTAssertNotNil(LinuxHelpContent.topic(.shortcuts))
    }

    func testNoMacOnlyWordsInLinuxHelp() {
        for topic in LinuxHelpContent.topics {
            let text = topic.blocks.flatMap(\.texts).joined(separator: " ")
            for word in ["Finder", "\u{2318}", "Full Disk Access", "Spotlight", "iCloud"] {
                XCTAssertFalse(text.contains(word), "\(topic.title) mentions \(word)")
            }
        }
    }

    func testSearchFindsTopics() {
        let results = HelpSearch.results(for: "rename", in: LinuxHelpContent.topics)
        XCTAssertTrue(results.contains { $0.topicID == .fileOperations })
    }

    func testShortcutKeysAreNotRepeated() {
        var seen: [String: String] = [:]
        for section in LinuxShortcuts.sections {
            for (keys, what) in section.shortcuts {
                for key in keys.components(separatedBy: " / ").flatMap({ $0.components(separatedBy: " or ") }) where key.contains("+") {
                    if let other = seen[key] { XCTFail("\(key) is listed for \(other) and \(what)") }
                    seen[key] = what
                }
            }
        }
    }

    func testSortMenuFieldsRoundTrip() {
        for field in ContextBar.sortFields {
            XCTAssertEqual(FileColumn(rawValue: field.rawValue), field)
        }
    }
}

final class ItemInfoCreatedTests: XCTestCase {
    func testCreationDateIsReadWhenKnown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oneroot-iteminfo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        let info = try ItemInfo.read(file, isDirectory: false, wantsText: false)
        // Some filesystems record no birth time: then it is nil, never made up.
        if let created = info.created {
            XCTAssertLessThan(abs(created.timeIntervalSinceNow), 60)
        }
        XCTAssertNotNil(info.modified)
    }
}
