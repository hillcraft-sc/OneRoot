import XCTest
@testable import OneRoot

final class SearchCriteriaMatcherTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/f")
    private let now = Date(timeIntervalSince1970: 1_793_000_000) // a Thursday in October 2026
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }()

    private func node(_ name: String, directory: Bool = false, size: Int64? = nil, modified: Date? = nil, tags: [String] = []) -> FileNode {
        FileNode(url: root.appendingPathComponent(name), name: name, isDirectory: directory, size: size, modificationDate: modified, kind: nil, tags: tags)
    }

    private func matcher(_ configure: (inout SearchCriteria) -> Void) throws -> SearchCriteriaMatcher {
        var criteria = SearchCriteria(root: root)
        configure(&criteria)
        return try SearchCriteriaMatcher(criteria, now: now, calendar: calendar)
    }

    func testNameModes() throws {
        XCTAssertTrue(try matcher { $0.pattern = "rep" }.matches(node("Report.txt")))
        XCTAssertFalse(try matcher { $0.pattern = "rep"; $0.caseSensitive = true }.matches(node("Report.txt")))
        XCTAssertTrue(try matcher { $0.pattern = "txt"; $0.patternMode = .endsWith }.matches(node("Report.txt")))
        XCTAssertTrue(try matcher { $0.pattern = #"^IMG_\d+"#; $0.patternMode = .regex }.matches(node("IMG_4012.jpg")))
        XCTAssertThrowsError(try matcher { $0.pattern = "("; $0.patternMode = .regex })
    }

    func testKindLeavesPlainFoldersOutButNotApps() throws {
        let images = try matcher { $0.kinds = [.images, .documents] }
        XCTAssertTrue(images.matches(node("a.HEIC")))
        XCTAssertTrue(images.matches(node("b.pdf")))
        XCTAssertFalse(images.matches(node("c.zip")))
        XCTAssertFalse(images.matches(node("Photos", directory: true)))
        let app = FileNode(url: root.appendingPathComponent("X.app"), name: "X.app", isDirectory: true, isPackage: true, size: nil, modificationDate: nil, kind: nil)
        XCTAssertTrue(try matcher { $0.kinds = [.apps] }.matches(app))
    }

    func testRelativeDatesStartAtTheCalendarBoundary() throws {
        let startOfMonth = SearchDateRange.thisMonth.start(now: now, calendar: calendar)
        let thisMonth = try matcher { $0.modifiedWithin = .thisMonth }
        XCTAssertTrue(thisMonth.matches(node("a", modified: startOfMonth)))
        XCTAssertFalse(thisMonth.matches(node("b", modified: startOfMonth.addingTimeInterval(-1))))
        XCTAssertFalse(thisMonth.matches(node("c", modified: nil)))
        XCTAssertEqual(SearchDateRange.today.start(now: now, calendar: calendar), calendar.startOfDay(for: now))
        XCTAssertLessThanOrEqual(SearchDateRange.thisYear.start(now: now, calendar: calendar), startOfMonth)
    }

    func testSizeExtensionTagsAndItemType() throws {
        let filters = try matcher {
            $0.minSizeBytes = 1_000
            $0.extensions = ["pdf"]
            $0.tags = ["red", "Work"]
        }
        XCTAssertTrue(filters.matches(node("a.PDF", size: 2_000, tags: ["Red", "work", "Blue"])))
        XCTAssertFalse(filters.matches(node("b.pdf", size: 2_000, tags: ["Red"])), "needs every tag")
        XCTAssertFalse(filters.matches(node("c.pdf", size: 10, tags: ["Red", "Work"])))
        XCTAssertFalse(try matcher { $0.itemType = .filesOnly }.matches(node("d", directory: true)))
    }
}

final class SearchCriteriaModelTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/f")

    func testHasFiltersIgnoresScopeToggles() {
        var criteria = SearchCriteria(root: root)
        criteria.includeHidden = true
        criteria.mode = .contents
        XCTAssertFalse(criteria.hasFilters)
        criteria.kinds = [.video]
        XCTAssertTrue(criteria.hasFilters)
        XCTAssertTrue(criteria.hasFiltersBesidesName)
        let cleared = criteria.clearingFilters()
        XCTAssertFalse(cleared.hasFilters)
        XCTAssertTrue(cleared.includeHidden)
        XCTAssertEqual(cleared.mode, .contents)
    }

    func testOlderSavedQueriesStillDecodeAndNewFieldsRoundTrip() throws {
        let old = #"{"root":"file:///tmp/f/","pattern":"x","mode":"nameAndMetadata"}"#
        let decoded = try JSONDecoder().decode(SearchCriteria.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.pattern, "x")
        XCTAssertEqual(decoded.kinds, [])
        XCTAssertNil(decoded.modifiedWithin)

        var criteria = SearchCriteria(root: root)
        criteria.kinds = [.images]
        criteria.modifiedWithin = .thisWeek
        criteria.tags = ["Red"]
        let roundTripped = try JSONDecoder().decode(SearchCriteria.self, from: JSONEncoder().encode(criteria))
        XCTAssertEqual(roundTripped, criteria)
    }
}

final class SearchChipBuilderTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/f")

    func testChipWording() {
        var criteria = SearchCriteria(root: root)
        criteria.pattern = #"^IMG_\d+"#
        criteria.patternMode = .regex
        criteria.caseSensitive = true
        criteria.kinds = [.documents, .images]
        criteria.modifiedWithin = .thisMonth
        criteria.minSizeBytes = 5_000_000
        criteria.extensions = ["pdf", "png"]
        criteria.tags = ["Red"]
        criteria.itemType = .filesOnly
        let titles = SearchChipBuilder.chips(for: criteria, context: .folder).map(\.title)
        XCTAssertEqual(titles, [
            #"Name matches /^IMG_\d+/ · Match Case"#,
            "Files only",
            "Kind: Images, Documents",
            "Extension: pdf, png",
            "Modified: This Month",
            "Size: over 5 MB",
            "Tag: Red",
        ])
    }

    func testAdvancedSearchAddsContentsAndScopeChipsTheFolderLeavesOut() {
        var criteria = SearchCriteria(root: root)
        criteria.mode = .contents
        criteria.pattern = "invoice"
        criteria.includeHidden = true
        criteria.includeCloudStorage = true
        XCTAssertEqual(SearchChipBuilder.chips(for: criteria, context: .advancedSearch).map(\.title), [
            "Contains text “invoice”", "Including hidden files", "Including cloud storage",
        ])
        XCTAssertEqual(SearchChipBuilder.chips(for: criteria, context: .folder).map(\.field), [.name])
    }

    func testRemovingClearsJustThatCondition() {
        var criteria = SearchCriteria(root: root)
        criteria.pattern = "a"
        criteria.patternMode = .startsWith
        criteria.tags = ["Red", "Work"]
        criteria.minSizeBytes = 1
        criteria.maxSizeBytes = 2
        let withoutName = SearchChipBuilder.removing(.name, from: criteria)
        XCTAssertEqual(withoutName.pattern, "")
        XCTAssertEqual(withoutName.patternMode, .contains)
        XCTAssertEqual(withoutName.tags, ["Red", "Work"])
        XCTAssertEqual(SearchChipBuilder.removing(.tag("red"), from: criteria).tags, ["Work"])
        let withoutSize = SearchChipBuilder.removing(.size, from: criteria)
        XCTAssertNil(withoutSize.minSizeBytes)
        XCTAssertNil(withoutSize.maxSizeBytes)
    }

    func testSizeWording() {
        XCTAssertEqual(SearchChipBuilder.sizeTitle(min: nil, max: 100_000), "Size: under 100 KB")
        XCTAssertEqual(SearchChipBuilder.sizeTitle(min: 1_000_000, max: 1_000_000_000), "Size: 1 MB – 1 GB")
        XCTAssertNil(SearchChipBuilder.sizeTitle(min: nil, max: nil))
    }
}

@MainActor
final class SearchHandoffTests: XCTestCase {
    func testHandoffIsTakenOnceAndStartsTheSearch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let center = SearchHandoffCenter()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SearchHandoffTests-\(UUID().uuidString)"))
        let viewModel = SearchViewModel(initialRoot: folder, defaults: defaults)
        var criteria = SearchCriteria(root: folder)
        criteria.kinds = [.images]

        center.hand(criteria)
        viewModel.takeHandoff(from: center)

        XCTAssertEqual(viewModel.criteria.kinds, [.images])
        XCTAssertTrue(viewModel.isSearching)
        XCTAssertNil(center.pending)
        viewModel.cancel()
    }
}
