import XCTest
@testable import OneRoot

final class RecentlyUsedIndexTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func xbel(_ bookmarks: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">
        \(bookmarks)
        </xbel>
        """.utf8)
    }

    func testParsesLocalBookmarksPreferringVisited() {
        let data = xbel("""
        <bookmark href="file:///home/u/My%20Doc.txt" added="2026-01-01T00:00:00Z" modified="2026-01-02T00:00:00Z" visited="2026-01-03T00:00:00Z"/>
        <bookmark href="file:///home/u/b.txt" added="2026-01-01T00:00:00Z" modified="2026-01-02T00:00:00.5Z"/>
        <bookmark href="https://example.com/x" added="2026-01-01T00:00:00Z" visited="2026-01-03T00:00:00Z"/>
        <bookmark href="file:///home/u/c.txt" added="not a date"/>
        """)
        let entries = RecentlyUsedIndex.entries(in: data)
        XCTAssertEqual(entries.map(\.path), ["/home/u/My Doc.txt", "/home/u/b.txt"])
        XCTAssertEqual(entries[0].lastUsed, ISO8601DateFormatter().date(from: "2026-01-03T00:00:00Z"))
    }

    func testGarbageYieldsNothing() {
        XCTAssertTrue(RecentlyUsedIndex.entries(in: Data("not xml".utf8)).isEmpty)
        XCTAssertTrue(RecentlyUsedIndex.entries(in: Data()).isEmpty)
    }

    func testFiltersByAgeRootAndExistence() throws {
        let now = ISO8601DateFormatter().date(from: "2026-02-01T00:00:00Z")!
        let fresh = dir.appendingPathComponent("fresh.txt")
        let old = dir.appendingPathComponent("old.txt")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        for url in [fresh, old, outside] { try Data().write(to: url) }
        defer { try? FileManager.default.removeItem(at: outside) }
        let missing = dir.appendingPathComponent("missing.txt")
        let file = dir.appendingPathComponent("recently-used.xbel")
        try xbel("""
        <bookmark href="\(fresh.absoluteString)" visited="2026-01-30T00:00:00Z"/>
        <bookmark href="\(old.absoluteString)" visited="2025-12-01T00:00:00Z"/>
        <bookmark href="\(missing.absoluteString)" visited="2026-01-30T00:00:00Z"/>
        <bookmark href="\(outside.absoluteString)" visited="2026-01-30T00:00:00Z"/>
        """).write(to: file)
        let index = RecentlyUsedIndex(xbelURL: file, now: { now })
        let found = index.recentlyUsed(withinDays: 30, under: [dir])
        XCTAssertEqual(found.map(\.path), [fresh.path])
    }

    func testMissingFileIsEmpty() {
        let index = RecentlyUsedIndex(xbelURL: dir.appendingPathComponent("nope.xbel"))
        XCTAssertTrue(index.recentlyUsed(withinDays: 30, under: [dir]).isEmpty)
        XCTAssertNil(index.paths(matching: "x", under: dir))
    }
}
