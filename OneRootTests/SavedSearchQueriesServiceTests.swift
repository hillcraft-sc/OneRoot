import XCTest
@testable import OneRoot

final class SavedSearchQueriesServiceTests: XCTestCase {
    private func makeService() -> SavedSearchQueriesService {
        SavedSearchQueriesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func makeQuery(name: String = "PDFs over 10MB") -> SavedSearchQuery {
        var criteria = SearchCriteria(root: URL(fileURLWithPath: "/Users/eric/Documents"))
        criteria.extensions = ["pdf"]
        criteria.minSizeBytes = 10_000_000
        return SavedSearchQuery(name: name, criteria: criteria)
    }

    func testLoadWithNoSavedDataReturnsEmpty() {
        let service = makeService()

        XCTAssertTrue(service.load().isEmpty)
    }

    func testUpsertThenLoadRoundTrips() {
        let service = makeService()
        let query = makeQuery()

        let result = service.upsert(query)

        XCTAssertEqual(result, [query])
        XCTAssertEqual(service.load(), [query])
        XCTAssertEqual(service.load().first?.criteria.extensions, ["pdf"])
    }

    func testUpsertWithExistingIDReplacesInPlace() {
        let service = makeService()
        var query = makeQuery()
        service.upsert(query)

        query.name = "Renamed"
        let result = service.upsert(query)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Renamed")
    }

    func testRemoveDeletesMatchingQuery() {
        let service = makeService()
        let query = makeQuery()
        service.upsert(query)

        let result = service.remove(id: query.id)

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(service.load().isEmpty)
    }

    func testRemoveWithUnknownIdLeavesListUnchanged() {
        let service = makeService()
        let query = makeQuery()
        service.upsert(query)

        let result = service.remove(id: UUID())

        XCTAssertEqual(result, [query])
    }
}
