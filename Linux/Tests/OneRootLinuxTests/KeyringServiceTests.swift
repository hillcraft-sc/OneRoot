import XCTest
@testable import OneRootLinux

/// Talks to the real desktop keyring, so it only runs when asked:
/// `ONEROOT_TEST_KEYRING=1` inside a session with an unlocked keyring
/// (`dbus-run-session -- sh -c 'echo x | gnome-keyring-daemon --unlock --components=secrets; swift test …'`).
final class KeyringServiceTests: XCTestCase {
    func testStoreLookupReplaceRemove() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ONEROOT_TEST_KEYRING"] == "1", "needs an unlocked desktop keyring")
        let service = KeyringService(service: "com.oneroot.test")
        let account = UUID().uuidString
        defer { service.remove(account: account) }
        XCTAssertNil(service.password(account: account))
        try service.store("first", account: account, label: "OneRoot test")
        XCTAssertEqual(service.password(account: account), "first")
        try service.store("second \u{00E9}\u{1F512}", account: account, label: "OneRoot test")
        XCTAssertEqual(service.password(account: account), "second \u{00E9}\u{1F512}")
        service.remove(account: account)
        XCTAssertNil(service.password(account: account))
    }

    func testMissingKeyringIsAnErrorNotACrash() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ONEROOT_TEST_NO_KEYRING"] == "1", "only where no Secret Service is running")
        let service = KeyringService(service: "com.oneroot.test")
        XCTAssertThrowsError(try service.store("x", account: "a", label: "l"))
        XCTAssertNil(service.password(account: "a"))
    }
}
