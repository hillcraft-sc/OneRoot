import Foundation

/// The host keys a server offered, as `ssh-keyscan` found them, with their
/// fingerprints for the user to check before trusting.
struct SSHHostKey: Equatable {
    var host: String
    var port: Int
    /// One line per key, as `ssh-keygen -l` prints them ("256 SHA256:… host (ED25519)").
    var fingerprints: [String]
    /// The `known_hosts` lines for exactly these keys.
    var knownHostsLines: String
}

enum SSHHostKeyError: LocalizedError {
    case toolNotFound(String)
    case noKeys(host: String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name): return "Couldn't find \(name) on this computer."
        case .noKeys(let host): return "\(host) didn't offer a host key. Check the address and port."
        case .failed(let message): return message.isEmpty ? "Command failed." : message
        }
    }
}

/// Handles a server's first-contact host key the way a Terminal would, but
/// with the fingerprint shown to the user first: nothing is trusted unless
/// they say so, and what's written to `known_hosts` is the exact key they
/// saw, so the copy that follows is verified against it. A host whose key
/// has *changed* is never handled here; the copy fails with ssh's warning.
struct SSHHostKeyService {
    var knownHostsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts")

    /// How `known_hosts` names a host: bare for port 22, `[host]:port` otherwise.
    static func knownHostsToken(host: String, port: Int) -> String {
        port == 22 ? host : "[\(host)]:\(port)"
    }

    /// The fingerprint lines in `ssh-keygen -l` output (blank and comment lines dropped).
    static func parseFingerprints(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The key lines in `ssh-keyscan` output (comments dropped).
    static func parseKeyLines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// True when `known_hosts` already has a key for the host.
    func isKnown(host: String, port: Int) async -> Bool {
        guard FileManager.default.fileExists(atPath: knownHostsURL.path),
              let result = try? await Self.run("/usr/bin/ssh-keygen", ["-F", Self.knownHostsToken(host: host, port: port), "-f", knownHostsURL.path]) else {
            return false
        }
        return result.status == 0
    }

    /// Asks the server for its host keys (no login happens).
    func scan(host: String, port: Int) async throws -> SSHHostKey {
        let scanned = try await Self.run("/usr/bin/ssh-keyscan", ["-T", "10", "-p", String(port), host])
        let lines = Self.parseKeyLines(scanned.stdout)
        guard !lines.isEmpty else { throw SSHHostKeyError.noKeys(host: host) }
        let joined = lines.joined(separator: "\n") + "\n"
        let printed = try await Self.run("/usr/bin/ssh-keygen", ["-l", "-f", "-"], stdin: joined)
        let fingerprints = Self.parseFingerprints(printed.stdout)
        guard printed.status == 0, !fingerprints.isEmpty else { throw SSHHostKeyError.failed(printed.stderr) }
        return SSHHostKey(host: host, port: port, fingerprints: fingerprints, knownHostsLines: joined)
    }

    /// Adds the keys the user approved to `known_hosts` (created 0600 in a 0700 `.ssh` if missing).
    func trust(_ key: SSHHostKey) throws {
        let directory = knownHostsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var existing = (try? String(contentsOf: knownHostsURL, encoding: .utf8)) ?? ""
        if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
        try (existing + key.knownHostsLines).write(to: knownHostsURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHostsURL.path)
    }

    private struct Output { var status: Int32; var stdout: String; var stderr: String }

    private static func run(_ path: String, _ arguments: [String], stdin: String? = nil) async throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw SSHHostKeyError.toolNotFound((path as NSString).lastPathComponent)
        }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let out = Pipe(), err = Pipe(), input = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = stdin == nil ? FileHandle.nullDevice : input
            try process.run()
            if let stdin {
                input.fileHandleForWriting.write(Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Output(status: process.terminationStatus,
                          stdout: String(decoding: outData, as: UTF8.self),
                          stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
