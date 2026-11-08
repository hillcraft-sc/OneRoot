import XCTest
@testable import OneRoot

final class SSHCopyProgressTests: XCTestCase {
    func testParsesScpMeterLine() {
        let line = "photo.jpg                                  45% 1234KB   1.2MB/s   00:05 ETA"
        XCTAssertEqual(SSHCopyProgress.parse(line), SSHCopyProgress(
            fileName: "photo.jpg", percent: 45, transferred: "1234KB", speed: "1.2MB/s", remaining: "00:05"))
    }

    func testParsesNameWithSpacesAndDone() {
        let line = "My Holiday Photo.jpg   100%   12MB  10.0MB/s   00:00"
        let parsed = SSHCopyProgress.parse(line)
        XCTAssertEqual(parsed?.fileName, "My Holiday Photo.jpg")
        XCTAssertEqual(parsed?.percent, 100)
    }

    func testShellCommandQuotesEveryWord() {
        XCTAssertEqual(SSHCopyService.shellCommand(["/usr/bin/scp", "it's here.txt"]), "'/usr/bin/scp' 'it'\\''s here.txt'")
    }

    func testIgnoresOtherText() {
        XCTAssertNil(SSHCopyProgress.parse(""))
        XCTAssertNil(SSHCopyProgress.parse("Warning: Permanently added 'host' to the list of known hosts."))
        XCTAssertNil(SSHCopyProgress.parse("100% of the disk is full"))
    }
}

final class SSHHostKeyServiceTests: XCTestCase {
    func testKnownHostsTokenBracketsNonDefaultPorts() {
        XCTAssertEqual(SSHHostKeyService.knownHostsToken(host: "example.com", port: 22), "example.com")
        XCTAssertEqual(SSHHostKeyService.knownHostsToken(host: "example.com", port: 2222), "[example.com]:2222")
    }

    func testParsingDropsCommentsAndBlankLines() {
        let scan = "# host:22 SSH-2.0-OpenSSH\nhost ssh-ed25519 AAAA\n\n"
        XCTAssertEqual(SSHHostKeyService.parseKeyLines(scan), ["host ssh-ed25519 AAAA"])
        XCTAssertEqual(SSHHostKeyService.parseFingerprints("256 SHA256:abc host (ED25519)\n"), ["256 SHA256:abc host (ED25519)"])
    }

    func testTrustAppendsToKnownHostsWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(".ssh/known_hosts")
        let service = SSHHostKeyService(knownHostsURL: file)
        let key = SSHHostKey(host: "h", port: 22, fingerprints: ["x"], knownHostsLines: "h ssh-ed25519 AAAA\n")
        try service.trust(key)
        try "no-newline-line".write(to: file, atomically: true, encoding: .utf8)
        try service.trust(key)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "no-newline-line\nh ssh-ed25519 AAAA\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }
}
