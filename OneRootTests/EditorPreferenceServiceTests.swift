import XCTest
@testable import OneRoot

final class EditorPreferenceServiceTests: XCTestCase {
    private func makeService() -> EditorPreferenceService {
        EditorPreferenceService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testBundleIdentifierWithNoSavedDataReturnsNil() {
        let service = makeService()

        XCTAssertNil(service.bundleIdentifier())
    }

    func testSetThenGetRoundTrips() {
        let service = makeService()

        service.setBundleIdentifier("com.microsoft.VSCode")

        XCTAssertEqual(service.bundleIdentifier(), "com.microsoft.VSCode")
    }

    func testSetNilClearsSavedValue() {
        let service = makeService()
        service.setBundleIdentifier("com.microsoft.VSCode")

        service.setBundleIdentifier(nil)

        XCTAssertNil(service.bundleIdentifier())
    }

    func testWorkingDirectoryFlagWithNoSavedDataReturnsNil() {
        let service = makeService()

        XCTAssertNil(service.workingDirectoryFlag())
    }

    func testWorkingDirectoryFlagSetThenGetRoundTrips() {
        let service = makeService()

        service.setWorkingDirectoryFlag("--new-window")

        XCTAssertEqual(service.workingDirectoryFlag(), "--new-window")
    }

    func testWorkingDirectoryFlagSetNilClearsSavedValue() {
        let service = makeService()
        service.setWorkingDirectoryFlag("--new-window")

        service.setWorkingDirectoryFlag(nil)

        XCTAssertNil(service.workingDirectoryFlag())
    }

    func testWorkingDirectoryFlagSetEmptyStringClearsSavedValue() {
        let service = makeService()
        service.setWorkingDirectoryFlag("--new-window")

        service.setWorkingDirectoryFlag("")

        XCTAssertNil(service.workingDirectoryFlag())
    }
}
