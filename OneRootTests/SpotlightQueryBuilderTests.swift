import XCTest
@testable import OneRoot

final class SpotlightQueryBuilderTests: XCTestCase {
    private func criteria(_ configure: (inout SearchCriteria) -> Void) -> SearchCriteria {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/tmp"))
        configure(&criteria)
        return criteria
    }

    func testPatternModesMapToWildcards() {
        XCTAssertEqual(SpotlightQueryBuilder.query(for: criteria { $0.pattern = "rep" }), #"kMDItemFSName == "*rep*"c"#)
        XCTAssertEqual(SpotlightQueryBuilder.query(for: criteria { $0.pattern = "rep"; $0.patternMode = .startsWith }), #"kMDItemFSName == "rep*"c"#)
        XCTAssertEqual(SpotlightQueryBuilder.query(for: criteria { $0.pattern = "rep"; $0.patternMode = .endsWith }), #"kMDItemFSName == "*rep"c"#)
    }

    func testCaseSensitiveDropsTheCaseInsensitiveModifier() {
        XCTAssertEqual(
            SpotlightQueryBuilder.query(for: criteria { $0.pattern = "Rep"; $0.caseSensitive = true }),
            #"kMDItemFSName == "*Rep*""#
        )
    }

    func testRegexCantBeExpressed() {
        XCTAssertNil(SpotlightQueryBuilder.query(for: criteria { $0.pattern = "^a.*z$"; $0.patternMode = .regex }))
    }

    func testNothingToSearchByIsNil() {
        XCTAssertNil(SpotlightQueryBuilder.query(for: criteria { _ in }))
        XCTAssertNil(SpotlightQueryBuilder.query(for: criteria { $0.maxSizeBytes = 100 }), "a maximum alone would drop folders")
    }

    func testExtensionsAndMinimumSizeCombine() {
        XCTAssertEqual(
            SpotlightQueryBuilder.query(for: criteria { $0.extensions = ["pdf", "docx"]; $0.minSizeBytes = 1_000 }),
            #"(kMDItemFSName == "*.pdf"c || kMDItemFSName == "*.docx"c) && kMDItemFSSize >= 1000"#
        )
    }

    func testSpecialCharactersAreEscaped() {
        XCTAssertEqual(SpotlightQueryBuilder.escape(#"a"b*c\d"#), #"a\"b\*c\\d"#)
        XCTAssertEqual(SpotlightQueryBuilder.query(for: criteria { $0.pattern = "*" }), #"kMDItemFSName == "*\**"c"#)
    }
}
