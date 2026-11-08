import XCTest
@testable import OneRoot

final class PinnedLocationsServiceTests: XCTestCase {
    private func makeService() -> PinnedLocationsService {
        PinnedLocationsService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testLoadWithNoSavedDataReturnsEmpty() {
        let service = makeService()

        XCTAssertTrue(service.load().isEmpty)
    }

    func testSaveThenLoadRoundTrips() {
        let service = makeService()
        let urls = [URL(fileURLWithPath: "/Users/test/Projects"), URL(fileURLWithPath: "/Volumes/USB/Backups")]

        service.save(urls)

        XCTAssertEqual(service.load(), urls)
    }

    func testSaveOverwritesPreviousValue() {
        let service = makeService()
        service.save([URL(fileURLWithPath: "/one")])

        service.save([URL(fileURLWithPath: "/two")])

        XCTAssertEqual(service.load(), [URL(fileURLWithPath: "/two")])
    }

    @MainActor
    func testStoreMatchesAFolderWithOrWithoutATrailingSlash() {
        let store = PinnedLocationsStore(service: makeService())
        store.toggle(URL(fileURLWithPath: "/Users/test/Projects"))

        XCTAssertTrue(store.isPinned(URL(string: "file:///Users/test/Projects/")!))

        store.toggle(URL(string: "file:///Users/test/Projects/")!)
        XCTAssertTrue(store.urls.isEmpty)
    }
}
