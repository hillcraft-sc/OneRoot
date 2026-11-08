import XCTest
@testable import OneRoot

/// Talks to a real sshd; skipped unless ONEROOT_TEST_SSH_PORT is set (see
/// docs/LINUX-DEV.md). It adds the test server's key to ~/.ssh/known_hosts,
/// so run it only on a throwaway machine and remove the entry afterwards.
final class SSHCopyLiveTests: XCTestCase {
    func testFirstContactThenCopyWithProgress() async throws {
        guard let portText = ProcessInfo.processInfo.environment["ONEROOT_TEST_SSH_PORT"], let port = Int(portText),
              let key = ProcessInfo.processInfo.environment["ONEROOT_TEST_SSH_KEY"],
              let remote = ProcessInfo.processInfo.environment["ONEROOT_TEST_SSH_DIR"] else {
            throw XCTSkip("no test sshd")
        }
        let hostKeys = SSHHostKeyService()
        let known = await hostKeys.isKnown(host: "127.0.0.1", port: port)
        XCTAssertFalse(known, "remove the old entry first")

        let scanned = try await hostKeys.scan(host: "127.0.0.1", port: port)
        XCTAssertFalse(scanned.fingerprints.isEmpty)
        XCTAssertTrue(scanned.fingerprints[0].contains("SHA256:"), scanned.fingerprints[0])
        try hostKeys.trust(scanned)
        let knownNow = await hostKeys.isKnown(host: "127.0.0.1", port: port)
        XCTAssertTrue(knownNow)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString).bin")
        try Data(count: 40_000_000).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        final class Box: @unchecked Sendable { var updates: [SSHCopyProgress] = [] }
        let box = Box()
        let lock = NSLock()
        let destination = SSHDestination(host: "127.0.0.1", port: port, username: NSUserName(), remotePath: remote, privateKeyPath: key)
        try await SSHCopyService().copy([source], to: destination, password: nil) { update in
            lock.lock(); box.updates.append(update); lock.unlock()
        }
        let copied = URL(fileURLWithPath: remote).appendingPathComponent(source.lastPathComponent)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copied.path)[.size] as? Int, 40_000_000)
        lock.lock(); defer { lock.unlock() }
        XCTAssertFalse(box.updates.isEmpty, "scp's meter should have been read")
        XCTAssertEqual(box.updates.last?.percent, 100)
    }
}
