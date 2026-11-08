import XCTest
@testable import OneRootLinux

final class NetworkHostAliasesTests: XCTestCase {
    func testNameComesFirstWithoutRepeats() {
        XCTAssertEqual(NetworkHostAliases.merged("nas.local", ["192.168.1.20", "nas.local", "192.168.1.20"]), ["nas.local", "192.168.1.20"])
    }

    func testAnAddressResolvesToItself() {
        XCTAssertEqual(NetworkHostAliases.addresses(of: "127.0.0.1"), ["127.0.0.1"])
    }

    func testAnUnresolvableNameIsJustItself() async {
        let accounts = await NetworkHostAliases.accounts(for: "No-Such-Host.invalid")
        XCTAssertEqual(accounts, ["no-such-host.invalid"])
    }
}
