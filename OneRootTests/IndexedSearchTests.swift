import XCTest
@testable import OneRoot

/// Returns canned paths in place of Spotlight, so the indexed search path
/// can be tested deterministically — including a stale index.
private final class FakeIndex: SearchIndexQuerying {
    var paths: [String]?
    private(set) var queries: [String] = []

    init(paths: [String]?) {
        self.paths = paths
    }

    func paths(matching query: String, under root: URL) -> [String]? {
        queries.append(query)
        return paths
    }
}

final class IndexedSearchTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        // Resolved, the way Spotlight reports paths (/private/var/…, not /var/…).
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @discardableResult
    private func write(_ relativePath: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private struct Outcome {
        var engine: SearchEngine?
        /// Matches reported before `.indexPhaseFinished` — i.e. from the index.
        var fromIndex: [String] = []
        /// Matches the full scan added afterwards (or all of them, without an index phase).
        var fromScan: [String] = []
        var indexPhaseCount: Int?
        var names: [String] { fromIndex + fromScan }
    }

    private func run(_ criteria: SearchCriteria, index: FakeIndex, useIndex: Bool = true) async throws -> Outcome {
        var outcome = Outcome()
        var inIndexPhase = false
        for try await event in SearchService(index: index).search(criteria, useIndex: useIndex) {
            switch event {
            case .engine(let reported):
                outcome.engine = reported
                inIndexPhase = reported == .spotlightIndex
            case .matched(let result):
                if inIndexPhase {
                    outcome.fromIndex.append(result.node.name)
                } else {
                    outcome.fromScan.append(result.node.name)
                }
            case .indexPhaseFinished(let matches):
                outcome.indexPhaseCount = matches
                inIndexPhase = false
            case .progress:
                break
            }
        }
        return outcome
    }

    func testIndexMatchesComeFirstThenTheScanAddsOnlyWhatTheIndexMissed() async throws {
        let report = try write("report.txt")
        try write("report-not-in-index.txt")
        let index = FakeIndex(paths: [report.path])

        let result = try await run(SearchCriteria(root: tempDirectory, pattern: "report"), index: index)

        XCTAssertEqual(result.engine, .spotlightIndex)
        XCTAssertEqual(result.fromIndex, ["report.txt"])
        XCTAssertEqual(result.indexPhaseCount, 1)
        XCTAssertEqual(result.fromScan, ["report-not-in-index.txt"], "no duplicate of report.txt")
        XCTAssertEqual(index.queries, [#"kMDItemFSName == "*report*"c"#])
    }

    func testIndexedSearchEndsWithTheSameResultsAsAPlainScan() async throws {
        let a = try write("Docs/report-a.txt")
        try write("Docs/Deep/report-b.txt")
        try write("report-c.txt")
        try write("unrelated.txt")
        let index = FakeIndex(paths: [a.path])
        let criteria = SearchCriteria(root: tempDirectory, pattern: "report")

        let indexed = try await run(criteria, index: index)
        let scanned = try await run(criteria, index: index, useIndex: false)

        XCTAssertEqual(Set(indexed.names), Set(scanned.names))
        XCTAssertEqual(indexed.names.count, scanned.names.count)
    }

    func testCandidatesAreRecheckedAgainstTheDiskAndTheCriteria() async throws {
        let match = try write("Report.txt")
        let wrongCase = try write("report.txt.bak") // case-sensitive search, so a lowercase-only name shouldn't match
        let deleted = tempDirectory.appendingPathComponent("Report-deleted.txt") // stale index entry
        let hiddenDir = try write(".cache/Report.txt")
        let outsideRoot = "/somewhere/else/Report.txt"
        let index = FakeIndex(paths: [match.path, wrongCase.path, deleted.path, hiddenDir.path, outsideRoot])

        let result = try await run(SearchCriteria(root: tempDirectory, pattern: "Report", caseSensitive: true), index: index)

        XCTAssertEqual(result.fromIndex, ["Report.txt"])
        XCTAssertEqual(result.fromScan, [], "the scan agrees: nothing else matches")
    }

    #if os(macOS) // Finder-hidden (UF_HIDDEN) folders are a macOS flag
    func testCandidatesInsideAFlagHiddenFolderAreSkippedLikeTheWalk() async throws {
        // Like ~/Library: no leading dot, but flagged hidden — the walk skips it.
        var flagged = tempDirectory.appendingPathComponent("Library", isDirectory: true)
        let inside = try write("Library/Logs/report.txt")
        var values = URLResourceValues()
        values.isHidden = true
        try flagged.setResourceValues(values)
        let visible = try write("Documents/report.txt")
        let index = FakeIndex(paths: [inside.path, visible.path])

        let indexed = try await run(SearchCriteria(root: tempDirectory, pattern: "report"), index: index)
        let walked = try await run(SearchCriteria(root: tempDirectory, pattern: "report"), index: index, useIndex: false)

        XCTAssertEqual(indexed.fromIndex, ["report.txt"])
        XCTAssertEqual(indexed.names, walked.names)
    }
    #endif

    func testFiltersStillApplyToCandidates() async throws {
        let pdf = try write("a.pdf")
        let txt = try write("a.txt")
        let folder = tempDirectory.appendingPathComponent("a-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = FakeIndex(paths: [pdf.path, txt.path, folder.path])

        var criteria = SearchCriteria(root: tempDirectory, pattern: "a")
        criteria.extensions = ["pdf"]
        let byExtension = try await run(criteria, index: index)
        XCTAssertEqual(byExtension.fromIndex, ["a.pdf"])

        criteria.extensions = []
        criteria.itemType = .foldersOnly
        let foldersOnly = try await run(criteria, index: index)
        XCTAssertEqual(foldersOnly.fromIndex, ["a-folder"])
    }

    func testUnindexedRootFallsBackToTheWalk() async throws {
        try write("report.txt")

        let result = try await run(SearchCriteria(root: tempDirectory, pattern: "report"), index: FakeIndex(paths: nil))

        XCTAssertEqual(result.engine, .fullScan(reason: "this location isn't indexed by Spotlight"))
        XCTAssertEqual(result.names, ["report.txt"])
    }

    func testIndexOffNeverQueriesIt() async throws {
        try write("report.txt")
        let index = FakeIndex(paths: [])

        let result = try await run(SearchCriteria(root: tempDirectory, pattern: "report"), index: index, useIndex: false)

        XCTAssertEqual(result.engine, .fullScan(reason: nil))
        XCTAssertEqual(result.names, ["report.txt"])
        XCTAssertEqual(index.queries, [])
    }

    func testEngineChoice() {
        let root = URL(fileURLWithPath: "/tmp")
        XCTAssertEqual(SearchService.engine(for: SearchCriteria(root: root, pattern: "a"), useIndex: true), .spotlightIndex)
        XCTAssertEqual(SearchService.engine(for: SearchCriteria(root: root, mode: .contents, pattern: "a"), useIndex: true), .fullScan(reason: nil))
        XCTAssertEqual(SearchService.engine(for: SearchCriteria(root: root, pattern: "a", includeHidden: true), useIndex: true),
                       .fullScan(reason: "Spotlight doesn't index hidden files"))
        XCTAssertEqual(SearchService.engine(for: SearchCriteria(root: root, pattern: "a+", patternMode: .regex), useIndex: true),
                       .fullScan(reason: "Spotlight can't search by regex"))
        XCTAssertEqual(SearchService.engine(for: SearchCriteria(root: root), useIndex: true),
                       .fullScan(reason: "Spotlight needs a name, extension, or minimum size to search by"))
    }
}
