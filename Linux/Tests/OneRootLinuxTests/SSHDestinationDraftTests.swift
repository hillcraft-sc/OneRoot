import XCTest
@testable import OneRoot
@testable import OneRootLinux

final class SSHDestinationDraftTests: XCTestCase {
    private func draft(host: String = "lab.example.com", port: String = "22", user: String = "ann", path: String = "~/inbox") -> SSHDestinationDraft {
        var draft = SSHDestinationDraft()
        draft.host = host; draft.port = port; draft.username = user; draft.remotePath = path
        return draft
    }

    func testValidDraftBecomesADestination() throws {
        let destination = try XCTUnwrap(draft(host: " lab.example.com ", port: " 2222 ", user: " ann ").destination())
        XCTAssertEqual(destination.host, "lab.example.com")
        XCTAssertEqual(destination.port, 2222)
        XCTAssertEqual(destination.username, "ann")
        XCTAssertEqual(destination.remotePath, "~/inbox")
    }

    func testProblemsAreNamed() {
        XCTAssertNotNil(draft(host: "  ").problem)
        XCTAssertNotNil(draft(host: "a b").problem)
        XCTAssertNotNil(draft(port: "0").problem)
        XCTAssertNotNil(draft(port: "70000").problem)
        XCTAssertNotNil(draft(port: "ssh").problem)
        XCTAssertNotNil(draft(user: " ").problem)
        XCTAssertNil(draft().problem)
        XCTAssertNil(draft(host: " ").destination())
    }

    func testEmptyRemotePathMeansHome() {
        XCTAssertEqual(draft(path: "  ").destination()?.remotePath, "~/")
    }

    func testSavedDestinationNamingAndKey() throws {
        var d = draft()
        let unnamed = try XCTUnwrap(d.saved())
        XCTAssertEqual(unnamed.name, "ann@lab.example.com")
        XCTAssertNil(unnamed.privateKeyPath)
        d.privateKeyPath = " ~/.ssh/id_ed25519 "
        let named = try XCTUnwrap(d.saved(name: "Lab"))
        XCTAssertEqual(named.name, "Lab")
        XCTAssertEqual(named.privateKeyPath, "~/.ssh/id_ed25519")
    }

    func testRoundTripFromSaved() {
        let saved = SavedSSHDestination(name: "Lab", host: "h", port: 2200, username: "u", remotePath: "/srv", privateKeyPath: "/k")
        let d = SSHDestinationDraft(saved, password: "pw")
        XCTAssertEqual(d.port, "2200")
        XCTAssertEqual(d.privateKeyPath, "/k")
        XCTAssertTrue(d.remembersPassword)
        XCTAssertFalse(SSHDestinationDraft(saved).remembersPassword)
    }
}
