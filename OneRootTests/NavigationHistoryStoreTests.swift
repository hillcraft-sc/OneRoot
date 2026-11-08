import XCTest
@testable import OneRoot

@MainActor
final class NavigationHistoryStoreTests: XCTestCase {
    private func makeStore(limit: Int? = nil) -> NavigationHistoryStore {
        let service = NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if let limit { service.saveLimit(limit) }
        return NavigationHistoryStore(service: service)
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    func testRecordPrependsMostRecentFirst() {
        let store = makeStore()

        store.record(url("/a"))
        store.record(url("/b"))
        store.record(url("/c"))

        XCTAssertEqual(store.entries, [url("/c"), url("/b"), url("/a")])
    }

    func testRecordMovesExistingEntryToFrontWithoutDuplicating() {
        let store = makeStore()

        store.record(url("/a"))
        store.record(url("/b"))
        store.record(url("/a"))

        XCTAssertEqual(store.entries, [url("/a"), url("/b")])
    }

    func testRecordingTheCurrentMostRecentEntryIsANoOp() {
        let store = makeStore()
        store.record(url("/a"))
        store.record(url("/b"))

        store.record(url("/b"))

        XCTAssertEqual(store.entries, [url("/b"), url("/a")])
    }

    func testHistoryIsCappedAtTheLimit() {
        let store = makeStore(limit: 5)

        for i in 0..<10 { store.record(url("/dir\(i)")) }

        XCTAssertEqual(store.entries.count, 5)
        XCTAssertEqual(store.entries.first, url("/dir9"))
        XCTAssertEqual(store.entries.last, url("/dir5"))
    }

    func testLoweringTheLimitTrimsExistingEntries() {
        let store = makeStore(limit: 20)
        for i in 0..<12 { store.record(url("/dir\(i)")) }

        store.setLimit(5)

        XCTAssertEqual(store.limit, 5)
        XCTAssertEqual(store.entries.count, 5)
        XCTAssertEqual(store.entries.first, url("/dir11"))
    }

    func testSetLimitClampsOutOfRangeValues() {
        let store = makeStore()

        store.setLimit(100_000)
        XCTAssertEqual(store.limit, NavigationHistoryService.limitRange.upperBound)
    }

    func testClearEmptiesHistory() {
        let store = makeStore()
        store.record(url("/a"))
        store.record(url("/b"))

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testEntriesAndLimitPersistAcrossStoreInstances() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = NavigationHistoryStore(service: NavigationHistoryService(defaults: defaults))
        first.setLimit(7)
        first.record(url("/a"))
        first.record(url("/b"))

        let second = NavigationHistoryStore(service: NavigationHistoryService(defaults: defaults))

        XCTAssertEqual(second.limit, 7)
        XCTAssertEqual(second.entries, [url("/b"), url("/a")])
    }
}
