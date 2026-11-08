import XCTest
@testable import OneRoot

final class SearchServiceTests: XCTestCase {
    private let service = SearchService()
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @discardableResult
    private func write(_ name: String, contents: String = "x", in directory: URL? = nil) throws -> URL {
        let url = (directory ?? tempDirectory).appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func matches(_ criteria: SearchCriteria) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        for try await event in service.search(criteria) {
            if case .matched(let result) = event { results.append(result) }
        }
        return results
    }

    // MARK: Name matching

    func testNameContainsMatch() async throws {
        try write("report.pdf")
        try write("notes.txt")

        let criteria = SearchCriteria(root: tempDirectory, pattern: "report", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["report.pdf"])
    }

    func testNameStartsWithAndEndsWith() async throws {
        try write("draft-report.txt")
        try write("report-final.txt")

        let startsWith = try await matches(SearchCriteria(root: tempDirectory, pattern: "report", patternMode: .startsWith))
        XCTAssertEqual(startsWith.map(\.node.name), ["report-final.txt"])

        let endsWith = try await matches(SearchCriteria(root: tempDirectory, pattern: "report.txt", patternMode: .endsWith))
        XCTAssertEqual(endsWith.map(\.node.name), ["draft-report.txt"])
    }

    func testNameRegexMatch() async throws {
        try write("file1.txt")
        try write("file2.txt")
        try write("other.txt")

        let criteria = SearchCriteria(root: tempDirectory, pattern: #"^file\d\.txt$"#, patternMode: .regex)
        let results = try await matches(criteria)

        XCTAssertEqual(Set(results.map(\.node.name)), ["file1.txt", "file2.txt"])
    }

    func testInvalidRegexThrows() async {
        let criteria = SearchCriteria(root: tempDirectory, pattern: "(unclosed", patternMode: .regex)
        do {
            _ = try await matches(criteria)
            XCTFail("expected an error for an invalid regex")
        } catch {
            XCTAssertTrue(error is SearchError)
        }
    }

    func testCaseSensitivity() async throws {
        try write("Report.txt")

        let insensitive = try await matches(SearchCriteria(root: tempDirectory, pattern: "report", patternMode: .contains, caseSensitive: false))
        XCTAssertEqual(insensitive.count, 1)

        let sensitive = try await matches(SearchCriteria(root: tempDirectory, pattern: "report", patternMode: .contains, caseSensitive: true))
        XCTAssertTrue(sensitive.isEmpty)
    }

    func testRecursesIntoSubfolders() async throws {
        let nested = tempDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("target.txt", in: nested)

        let criteria = SearchCriteria(root: tempDirectory, pattern: "target", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["target.txt"])
    }

    func testItemTypeFilterFoldersOnly() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try write("Projects.txt")

        let criteria = SearchCriteria(root: tempDirectory, pattern: "Projects", patternMode: .contains, itemType: .foldersOnly)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["Projects"])
    }

    func testItemTypeFilterFilesOnly() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try write("Projects.txt")

        let criteria = SearchCriteria(root: tempDirectory, pattern: "Projects", patternMode: .contains, itemType: .filesOnly)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["Projects.txt"])
    }

    func testNameSearchMatchesFolders() async throws {
        let desktop = tempDirectory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try write("Desktop.txt") // a file that merely contains the same word shouldn't be conflated with the folder match

        let criteria = SearchCriteria(root: tempDirectory, pattern: "Desktop", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertEqual(Set(results.map(\.node.name)), ["Desktop", "Desktop.txt"])
        XCTAssertEqual(results.first { $0.node.name == "Desktop" }?.node.isDirectory, true)
    }

    func testContentSearchDoesNotMatchFolderNames() async throws {
        let needle = tempDirectory.appendingPathComponent("needle", isDirectory: true)
        try FileManager.default.createDirectory(at: needle, withIntermediateDirectories: true)
        try write("notes.txt", contents: "no match here", in: needle)

        let criteria = SearchCriteria(root: tempDirectory, mode: .contents, pattern: "needle", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: Metadata filters

    func testExtensionFilter() async throws {
        try write("a.txt")
        try write("b.pdf")

        let criteria = SearchCriteria(root: tempDirectory, extensions: ["pdf"])
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["b.pdf"])
    }

    func testSizeFilter() async throws {
        try write("small.txt", contents: "x")
        try write("large.txt", contents: String(repeating: "x", count: 1000))

        let criteria = SearchCriteria(root: tempDirectory, minSizeBytes: 500)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.node.name), ["large.txt"])
    }

    func testHiddenFilesExcludedByDefault() async throws {
        try write(".hidden.txt")
        try write("visible.txt")

        let results = try await matches(SearchCriteria(root: tempDirectory))
        XCTAssertEqual(results.map(\.node.name), ["visible.txt"])
    }

    func testHiddenFilesIncludedWhenRequested() async throws {
        try write(".hidden.txt")

        let results = try await matches(SearchCriteria(root: tempDirectory, includeHidden: true))
        XCTAssertEqual(results.map(\.node.name), [".hidden.txt"])
    }

    func testMissingRootThrows() async {
        let criteria = SearchCriteria(root: tempDirectory.appendingPathComponent("does-not-exist"))
        do {
            _ = try await matches(criteria)
            XCTFail("expected an error for a missing root")
        } catch {
            XCTAssertTrue(error is SearchError)
        }
    }

    // MARK: Content search

    func testContentSearchFindsMatchingLineWithLineNumber() async throws {
        try write("notes.txt", contents: "first line\nsecond line has needle\nthird line")

        let criteria = SearchCriteria(root: tempDirectory, mode: .contents, pattern: "needle", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.contentMatch?.lineNumber, 2)
        XCTAssertEqual(results.first?.contentMatch?.snippet, "second line has needle")
    }

    func testContentSearchReportsOneRowPerMatchingLine() async throws {
        try write("notes.txt", contents: "needle one\nno match\nneedle two")

        let criteria = SearchCriteria(root: tempDirectory, mode: .contents, pattern: "needle", patternMode: .contains)
        let results = try await matches(criteria)

        XCTAssertEqual(results.map(\.contentMatch?.lineNumber), [1, 3])
    }

    func testContentSearchSkipsNonTextFiles() async throws {
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: tempDirectory.appendingPathComponent("image.png"))

        var lastProgress: (folders: Int, files: Int, skipped: Int)?
        let criteria = SearchCriteria(root: tempDirectory, mode: .contents, pattern: "anything", patternMode: .contains)
        for try await event in service.search(criteria) {
            if case .progress(let folders, let files, let skipped, _) = event {
                lastProgress = (folders, files, skipped)
            }
        }

        XCTAssertEqual(lastProgress?.skipped, 1)
    }
}
