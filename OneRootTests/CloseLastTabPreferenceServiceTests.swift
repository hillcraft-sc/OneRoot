import XCTest
@testable import OneRoot

final class CloseLastTabPreferenceServiceTests: XCTestCase {
    private func makeService() -> CloseLastTabPreferenceService {
        CloseLastTabPreferenceService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testShouldWarnWithNoSavedDataDefaultsToTrue() {
        let service = makeService()

        XCTAssertTrue(service.shouldWarn)
    }

    func testSetShouldWarnFalseThenReadRoundTrips() {
        let service = makeService()

        service.setShouldWarn(false)

        XCTAssertFalse(service.shouldWarn)
    }

    func testSetShouldWarnOverwritesPreviousValue() {
        let service = makeService()
        service.setShouldWarn(false)

        service.setShouldWarn(true)

        XCTAssertTrue(service.shouldWarn)
    }
}
