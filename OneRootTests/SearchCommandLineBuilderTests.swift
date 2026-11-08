import XCTest
@testable import OneRoot

final class SearchCommandLineBuilderTests: XCTestCase {
    private let builder = SearchCommandLineBuilder()

    func testNameContainsProducesFindWithIname() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/Users/eric/Documents"))
        criteria.pattern = "report"

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.hasPrefix("find '/Users/eric/Documents'"))
        XCTAssertTrue(command.contains("-iname '*report*'"))
    }

    func testHiddenFilesExcludedByDefault() {
        let criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.contains("-not -path '*/.*'"))
    }

    func testIncludeHiddenOmitsHiddenExclusion() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.includeHidden = true

        let command = builder.command(for: criteria)

        XCTAssertFalse(command.contains("-not -path"))
    }

    func testItemTypeAddsTypeFlag() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.itemType = .filesOnly

        XCTAssertTrue(builder.command(for: criteria).contains("-type f"))

        criteria.itemType = .foldersOnly
        XCTAssertTrue(builder.command(for: criteria).contains("-type d"))
    }

    func testRegexModeUsesExtendedRegexFlag() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.pattern = #"\.pdf$"#
        criteria.patternMode = .regex

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.contains("-E -iregex"))
    }

    func testExtensionsAddOredInameClauses() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.extensions = ["pdf", "docx"]

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.contains("-iname '*.pdf' -o -iname '*.docx'"))
    }

    func testSizeFiltersProduceFindSizeFlags() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.minSizeBytes = 1000
        criteria.maxSizeBytes = 5000

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.contains("-size +1000c"))
        XCTAssertTrue(command.contains("-size -5000c"))
    }

    func testContentsModeProducesGrepCommand() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/Users/eric/Projects"))
        criteria.mode = .contents
        criteria.pattern = "TODO"
        criteria.includeHidden = true

        let command = builder.command(for: criteria)

        XCTAssertEqual(command, "grep -r -n -i -F 'TODO' '/Users/eric/Projects'")
    }

    func testContentsModeCaseSensitiveOmitsDashI() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.mode = .contents
        criteria.pattern = "TODO"
        criteria.caseSensitive = true

        let command = builder.command(for: criteria)

        XCTAssertFalse(command.contains(" -i "))
    }

    func testPatternWithSingleQuoteIsSafelyEscaped() {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        criteria.pattern = "it's"

        let command = builder.command(for: criteria)

        XCTAssertTrue(command.contains("it'\\''s"))
    }
}
