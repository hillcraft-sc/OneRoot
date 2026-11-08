import XCTest
@testable import OneRootLinux

final class NetworkBrowserTests: XCTestCase {
    func testKeepsOnlyUsableAddressesMergesDuplicatesAndSorts() {
        let found = NetworkBrowser.servers(from: [
            (name: "nas", target: "smb://nas.local/"),
            (name: "Backup", target: "sftp://backup.local/"),
            (name: "nas (again)", target: "smb://nas.local/"),
            (name: "no address", target: nil),
            (name: "empty", target: "  "),
            (name: "loop", target: "network:///"),
            (name: "", target: "dav://files.local/"),
        ])
        XCTAssertEqual(found.map(\.address), ["sftp://backup.local/", "dav://files.local/", "smb://nas.local/"])
        XCTAssertEqual(found.map(\.name), ["Backup", "dav://files.local/", "nas"])
        XCTAssertEqual(found.first?.kind, "SFTP")
    }
}
