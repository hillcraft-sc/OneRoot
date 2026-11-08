import XCTest
@testable import OneRoot

final class HiddenFilesPreferenceServiceTests: XCTestCase {
    private func makeService() -> HiddenFilesPreferenceService {
        HiddenFilesPreferenceService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testLoadWithNoSavedDataReturnsFalse() {
        let service = makeService()

        XCTAssertFalse(service.load())
    }

    func testSaveThenLoadRoundTrips() {
        let service = makeService()

        service.save(true)

        XCTAssertTrue(service.load())
    }

    func testSaveOverwritesPreviousValue() {
        let service = makeService()
        service.save(true)

        service.save(false)

        XCTAssertFalse(service.load())
    }
}
