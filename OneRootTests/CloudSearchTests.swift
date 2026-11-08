#if os(macOS) // iCloud placeholders (SF_DATALESS) are Apple-only
import XCTest
@testable import OneRoot

private final class CloudFakeIndex: SearchIndexQuerying {
    var paths: [String]?
    init(paths: [String]?) { self.paths = paths }
    func paths(matching query: String, under root: URL) -> [String]? { paths }
}

final class CloudSearchTests: XCTestCase {
    private var root: URL!
    private var cloud: URL!

    override func setUpWithError() throws {
        // Resolved, the way Spotlight reports paths (/private/var/…).
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        // Like ~/Library: no leading dot, but flagged hidden, so a search skips it.
        var library = root.appendingPathComponent("Library", isDirectory: true)
        cloud = library.appendingPathComponent("CloudStorage/Nextcloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        var hidden = URLResourceValues()
        hidden.isHidden = true
        try library.setResourceValues(hidden)
        try "needle".write(to: root.appendingPathComponent("Documents/report-local.txt"), atomically: true, encoding: .utf8)
        try "needle".write(to: cloud.appendingPathComponent("report-cloud.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Outcome {
        var names: [String] = []
        var cloudOnly: [String] = []
        var fromIndex: [String] = []
        var notDownloaded = 0
    }

    private func run(
        _ criteria: SearchCriteria, index: SearchIndexQuerying = CloudFakeIndex(paths: nil), useIndex: Bool = false,
        isDataless: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) async throws -> Outcome {
        let cloudURL = cloud!
        let service = SearchService(index: index, cloudLocations: { [cloudURL] }, isDataless: isDataless)
        var outcome = Outcome()
        var inIndexPhase = false
        for try await event in service.search(criteria, useIndex: useIndex) {
            switch event {
            case .engine(let engine): inIndexPhase = engine == .spotlightIndex
            case .matched(let result):
                outcome.names.append(result.node.name)
                if result.isCloudOnly { outcome.cloudOnly.append(result.node.name) }
                if inIndexPhase { outcome.fromIndex.append(result.node.name) }
            case .indexPhaseFinished: inIndexPhase = false
            case .progress(_, _, _, let notDownloaded): outcome.notDownloaded = notDownloaded
            }
        }
        return outcome
    }

    func testCloudStorageIsOffByDefaultSoItsFilesAreNotFound() async throws {
        let result = try await run(SearchCriteria(root: root, pattern: "report"))

        XCTAssertEqual(result.names, ["report-local.txt"])
    }

    func testIncludingCloudStorageFindsItsFilesToo() async throws {
        let result = try await run(SearchCriteria(root: root, pattern: "report", includeCloudStorage: true))

        XCTAssertEqual(Set(result.names), ["report-local.txt", "report-cloud.txt"])
        XCTAssertEqual(result.names.count, 2, "no duplicates")
    }

    func testIncludingHiddenFilesAlreadyCoversItAndDoesNotDoubleCount() async throws {
        let result = try await run(SearchCriteria(root: root, pattern: "report", includeHidden: true, includeCloudStorage: true))

        XCTAssertEqual(result.names.sorted(), ["report-cloud.txt", "report-local.txt"])
    }

    func testSearchingInsideTheCloudFolderIsNotWalkedTwice() async throws {
        let result = try await run(SearchCriteria(root: cloud, pattern: "report", includeCloudStorage: true))

        XCTAssertEqual(result.names, ["report-cloud.txt"])
    }

    func testACloudFolderOutsideTheSearchRootIsNotSearched() async throws {
        let result = try await run(SearchCriteria(root: root.appendingPathComponent("Documents"), pattern: "report", includeCloudStorage: true))

        XCTAssertEqual(result.names, ["report-local.txt"])
    }

    func testWhichCloudRootsAreIncluded() {
        let locations = [cloud!, URL(fileURLWithPath: "/elsewhere/Cloud")]
        XCTAssertEqual(SearchService.includedCloudRoots(for: SearchCriteria(root: root, includeCloudStorage: true), among: locations), [cloud])
        XCTAssertEqual(SearchService.includedCloudRoots(for: SearchCriteria(root: URL(fileURLWithPath: "/"), includeCloudStorage: true), among: locations).count, 2, "a whole-volume search contains them all")
        XCTAssertEqual(SearchService.includedCloudRoots(for: SearchCriteria(root: root), among: locations), [], "off by default")
        XCTAssertEqual(SearchService.includedCloudRoots(for: SearchCriteria(root: cloud, includeCloudStorage: true), among: locations), [], "already inside it")
    }

    // MARK: Spotlight's first results

    func testSpotlightResultsInsideCloudFoldersAreShownWhenIncluded() async throws {
        let cloudFile = cloud.appendingPathComponent("report-cloud.txt")
        let index = CloudFakeIndex(paths: [cloudFile.path])

        let with = try await run(SearchCriteria(root: root, pattern: "report", includeCloudStorage: true), index: index, useIndex: true)
        let without = try await run(SearchCriteria(root: root, pattern: "report"), index: index, useIndex: true)

        XCTAssertEqual(with.fromIndex, ["report-cloud.txt"])
        XCTAssertEqual(with.names.filter { $0 == "report-cloud.txt" }.count, 1, "the walk doesn't repeat what the index found")
        XCTAssertEqual(without.fromIndex, [], "still skipped as hidden when not included")
    }

    func testSpotlightResultsStillSkipHiddenFoldersInsideTheCloudFolder() async throws {
        try FileManager.default.createDirectory(at: cloud.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        let hiddenInside = cloud.appendingPathComponent(".cache/report-cached.txt")
        try "x".write(to: hiddenInside, atomically: true, encoding: .utf8)

        let result = try await run(SearchCriteria(root: root, pattern: "report", includeCloudStorage: true), index: CloudFakeIndex(paths: [hiddenInside.path]), useIndex: true)

        XCTAssertEqual(result.fromIndex, [])
    }

    // MARK: Never download

    func testContentSearchNeverOpensPlaceholdersAndCountsThem() async throws {
        let placeholder = cloud.appendingPathComponent("report-cloud.txt")

        let result = try await run(
            SearchCriteria(root: root, mode: .contents, pattern: "needle", includeCloudStorage: true),
            isDataless: { $0.resolvingSymlinksInPath().path == placeholder.resolvingSymlinksInPath().path }
        )

        XCTAssertEqual(result.names, ["report-local.txt"], "the placeholder's contents weren't read")
        XCTAssertEqual(result.notDownloaded, 1)
    }

    func testNameSearchFindsPlaceholdersAndMarksThemCloudOnly() async throws {
        let placeholder = cloud.appendingPathComponent("report-cloud.txt")

        let result = try await run(
            SearchCriteria(root: root, pattern: "report", includeCloudStorage: true),
            isDataless: { $0.resolvingSymlinksInPath().path == placeholder.resolvingSymlinksInPath().path }
        )

        XCTAssertEqual(Set(result.names), ["report-local.txt", "report-cloud.txt"])
        XCTAssertEqual(result.cloudOnly, ["report-cloud.txt"])
    }

    func testPlaceholderDetectionReadsTheDatalessFlag() {
        XCTAssertTrue(SearchService.isDataless(flags: 0x4000_0000))
        XCTAssertTrue(SearchService.isDataless(flags: 0x4000_0000 | 0x20)) // alongside other flags
        XCTAssertFalse(SearchService.isDataless(flags: 0))
        XCTAssertFalse(SearchService.isDataless(flags: 0x20))
    }

    func testARealOrdinaryFileIsNotAPlaceholder() {
        XCTAssertFalse(SearchService.fileIsDataless(cloud.appendingPathComponent("report-cloud.txt")))
    }
}

final class SearchCriteriaCodingTests: XCTestCase {
    func testQueriesSavedBeforeCloudStorageExistedStillLoad() throws {
        let old = #"{"root":"file:///Users/eric/","mode":"nameAndMetadata","pattern":"report","patternMode":"contains","caseSensitive":true,"itemType":"filesOnly","extensions":["pdf"],"includeHidden":true}"#

        let criteria = try JSONDecoder().decode(SearchCriteria.self, from: Data(old.utf8))

        XCTAssertEqual(criteria.pattern, "report")
        XCTAssertEqual(criteria.extensions, ["pdf"])
        XCTAssertTrue(criteria.caseSensitive)
        XCTAssertTrue(criteria.includeHidden)
        XCTAssertFalse(criteria.includeCloudStorage, "off for anything saved before it existed")
    }

    func testRoundTripKeepsTheCloudSetting() throws {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/Users/eric"), pattern: "x")
        criteria.includeCloudStorage = true
        criteria.minSizeBytes = 1_000

        let decoded = try JSONDecoder().decode(SearchCriteria.self, from: JSONEncoder().encode(criteria))

        XCTAssertEqual(decoded, criteria)
        XCTAssertTrue(decoded.includeCloudStorage)
    }
}
#endif
