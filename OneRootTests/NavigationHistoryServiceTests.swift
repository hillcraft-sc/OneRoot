import XCTest
@testable import OneRoot

final class NavigationHistoryServiceTests: XCTestCase {
    private func makeService() -> NavigationHistoryService {
        NavigationHistoryService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testLimitWithNoSavedValueIsTwenty() {
        XCTAssertEqual(makeService().limit, 20)
        XCTAssertEqual(NavigationHistoryService.defaultLimit, 20)
    }

    func testSaveAndLoadEntriesRoundTrips() {
        let service = makeService()
        let urls = [
            URL(fileURLWithPath: "/Users/eric"),
            URL(fileURLWithPath: "/Applications"),
        ]

        service.saveEntries(urls)

        XCTAssertEqual(service.loadEntries(), urls)
    }

    func testSaveLimitClampsToRange() {
        let service = makeService()

        service.saveLimit(9_999)
        XCTAssertEqual(service.limit, NavigationHistoryService.limitRange.upperBound)

        service.saveLimit(1)
        XCTAssertEqual(service.limit, NavigationHistoryService.limitRange.lowerBound)
    }

    func testCorruptStoredLimitReadsBackClamped() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(0, forKey: "com.oneroot.navigationHistoryLimit")

        let service = NavigationHistoryService(defaults: defaults)

        XCTAssertEqual(service.limit, NavigationHistoryService.limitRange.lowerBound)
    }
}
