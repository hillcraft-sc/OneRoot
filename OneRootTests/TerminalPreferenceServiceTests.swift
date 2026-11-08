import XCTest
@testable import OneRoot

final class TerminalPreferenceServiceTests: XCTestCase {
    private func makeService() -> TerminalPreferenceService {
        TerminalPreferenceService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testBundleIdentifierWithNoSavedDataReturnsNil() {
        let service = makeService()

        XCTAssertNil(service.bundleIdentifier())
    }

    func testSetThenGetRoundTrips() {
        let service = makeService()

        service.setBundleIdentifier("com.googlecode.iterm2")

        XCTAssertEqual(service.bundleIdentifier(), "com.googlecode.iterm2")
    }

    func testSetNilClearsSavedValue() {
        let service = makeService()
        service.setBundleIdentifier("com.googlecode.iterm2")

        service.setBundleIdentifier(nil)

        XCTAssertNil(service.bundleIdentifier())
    }

    func testWorkingDirectoryFlagWithNoSavedDataReturnsNil() {
        let service = makeService()

        XCTAssertNil(service.workingDirectoryFlag())
    }

    func testWorkingDirectoryFlagSetThenGetRoundTrips() {
        let service = makeService()

        service.setWorkingDirectoryFlag("--working-directory")

        XCTAssertEqual(service.workingDirectoryFlag(), "--working-directory")
    }

    func testWorkingDirectoryFlagSetNilClearsSavedValue() {
        let service = makeService()
        service.setWorkingDirectoryFlag("--working-directory")

        service.setWorkingDirectoryFlag(nil)

        XCTAssertNil(service.workingDirectoryFlag())
    }

    func testWorkingDirectoryFlagSetEmptyStringClearsSavedValue() {
        let service = makeService()
        service.setWorkingDirectoryFlag("--working-directory")

        service.setWorkingDirectoryFlag("")

        XCTAssertNil(service.workingDirectoryFlag())
    }
}
