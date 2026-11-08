import XCTest
@testable import OneRoot

final class OneRootTests: XCTestCase {
    func testAppConfigIdentity() {
        XCTAssertEqual(AppConfig.displayName, "OneRoot")
        XCTAssertFalse(AppConfig.bundleIdentifier.isEmpty)
    }
}
