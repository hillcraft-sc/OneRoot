import Foundation

struct SSHDestination {
    var host: String
    var port: Int
    var username: String
    var remotePath: String
    var privateKeyPath: String?
}

/// What scp's own progress meter says about the file it is sending now.
/// (scp sends several files one after another and doesn't report the total.)
struct SSHCopyProgress: Equatable, Sendable {
    var fileName: String
    var percent: Int
    var transferred: String
    var speed: String
    var remaining: String

    /// Reads one refresh of scp's meter, e.g.
    /// `photo.jpg        45%  1234KB   1.2MB/s   00:05 ETA`. Nil for any other text.
    static func parse(_ line: String) -> SSHCopyProgress? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let percentIndex = parts.firstIndex(where: { $0.hasSuffix("%") && Int($0.dropLast()) != nil }),
              percentIndex >= 1, parts.count >= percentIndex + 4,
              let percent = Int(parts[percentIndex].dropLast()), (0...100).contains(percent),
              parts[percentIndex + 2].hasSuffix("/s") else { return nil }
        return SSHCopyProgress(
            fileName: parts[..<percentIndex].joined(separator: " "),
            percent: percent,
            transferred: parts[percentIndex + 1],
            speed: parts[percentIndex + 2],
            remaining: parts[percentIndex + 3]
        )
    }
}

enum SSHCopyError: LocalizedError {
    case scpNotFound
    case sshCopyIdNotFound
    case noPrivateKey
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .scpNotFound:
            return "Couldn't find scp on this computer."
        case .sshCopyIdNotFound:
            return "Couldn't find ssh-copy-id on this computer."
        case .noPrivateKey:
            return "Add a private key above first — there's nothing to install without one."
        case .failed(let message):
            return message.isEmpty ? "Command failed." : message
        }
    }
}

/// Copies local files/folders to a remote host via `scp`, and can push a
/// local public key out to a remote host's `authorized_keys` via
/// `ssh-copy-id` — both system binaries, run the same way a Terminal
/// invocation would.
///
/// There's no tty attached, so `ssh` can't show its normal interactive
/// password/passphrase prompt. When `password` is non-nil, it's supplied
/// via `SSH_ASKPASS`/`SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+, which every
/// macOS 14+ system ships) — the same non-interactive prompt mechanism
/// `ssh` itself uses under a GUI session, just backed by a throwaway script
/// instead of a real prompt. The same value is offered for whatever `ssh`
/// asks for — the account password or a private key's passphrase — since
/// this only collects one secret per destination.
struct SSHCopyService {
    private static let scpPath = "/usr/bin/scp"
    private static let sshCopyIdPath = "/usr/bin/ssh-copy-id"
    private static let scriptPath = "/usr/bin/script"

    /// `arguments` as one shell command line, each word single-quoted.
    static func shellCommand(_ words: [String]) -> String {
        words.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }

    /// The first key found among the common default names in `~/.ssh` —
    /// used to prefill "Copy via SSH" so key-based lab/server logins that
    /// already work from Terminal work here without typing a path.
    static func defaultPrivateKeyPath() -> String? {
        let sshDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        for name in ["id_ed25519", "id_ecdsa", "id_rsa"] {
            let candidate = sshDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    /// `progress` gets scp's own meter as it sends (scp only prints it to a
    /// terminal, so it is run on a pseudo-terminal when this is given).
    /// Cancelling the task stops scp.
    func copy(_ fileURLs: [URL], to destination: SSHDestination, password: String?,
              progress: (@Sendable (SSHCopyProgress) -> Void)? = nil) async throws {
        guard FileManager.default.isExecutableFile(atPath: Self.scpPath) else {
            throw SSHCopyError.scpNotFound
        }

        var arguments = ["-r", "-P", String(destination.port), "-o", "ConnectTimeout=15"]
        if let privateKeyPath = destination.privateKeyPath, !privateKeyPath.isEmpty {
            // `-i` picks the key; `IdentitiesOnly=yes` stops `ssh` from
            // also offering every other agent identity first — without it,
            // a server with several authorized keys can hit "too many
            // authentication failures" before this one is even tried.
            arguments += ["-i", (privateKeyPath as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
        }
        arguments += fileURLs.map(\.path)
        arguments.append("\(destination.username)@\(destination.host):\(destination.remotePath)")

        try await run(Self.scpPath, arguments: arguments, password: password, captureStdout: false, progress: progress)
    }

    /// Pushes `destination.privateKeyPath`'s matching public key
    /// (`<path>.pub`) into the destination's `authorized_keys`, via the
    /// system `ssh-copy-id` — the same "push my key so I stop needing a
    /// password" step you'd otherwise run by hand in Terminal. Needs the
    /// account password (there's no key on the server yet to authenticate
    /// with). Idempotent: `ssh-copy-id` skips keys that are already
    /// installed, so this is safe to run even if the server may already
    /// have it.
    func installKey(to destination: SSHDestination, password: String?) async throws {
        guard let privateKeyPath = destination.privateKeyPath, !privateKeyPath.isEmpty else {
            throw SSHCopyError.noPrivateKey
        }
        guard FileManager.default.isExecutableFile(atPath: Self.sshCopyIdPath) else {
            throw SSHCopyError.sshCopyIdNotFound
        }

        let arguments = [
            "-i", (privateKeyPath as NSString).expandingTildeInPath,
            "-p", String(destination.port),
            "-o", "ConnectTimeout=15",
            "\(destination.username)@\(destination.host)",
        ]

        try await run(Self.sshCopyIdPath, arguments: arguments, password: password, captureStdout: true)
    }

    /// Runs `executablePath` with `arguments`, optionally answering
    /// password/passphrase prompts via a throwaway `SSH_ASKPASS` script.
    /// `captureStdout` folds stdout into the same error text as stderr —
    /// `ssh-copy-id` reports its own failures on stdout, unlike `scp`.
    private func run(_ executablePath: String, arguments: [String], password: String?, captureStdout: Bool,
                     progress: (@Sendable (SSHCopyProgress) -> Void)? = nil) async throws {
        let askpassScript = try password.flatMap { $0.isEmpty ? nil : $0 }.map(Self.makeAskpassScript)
        defer {
            if let askpassScript {
                try? FileManager.default.removeItem(at: askpassScript.deletingLastPathComponent())
            }
        }

        let process = Process()
        let cancellation = ProcessCancellation(process)
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice

                let errorPipe = Pipe()
                process.standardError = errorPipe
                process.standardOutput = captureStdout ? errorPipe : FileHandle.nullDevice

                // scp draws its progress meter only when it runs in the
                // foreground of a terminal, so run it under `script`, which
                // provides one. Its output (meter and any errors) then comes
                // back on stdout.
                var meter: ProgressReader?
                if let progress, !captureStdout, FileManager.default.isExecutableFile(atPath: Self.scriptPath) {
                    process.executableURL = URL(fileURLWithPath: Self.scriptPath)
                    process.arguments = ["-q", "-e", "-f", "-c", Self.shellCommand([executablePath] + arguments), "/dev/null"]
                    meter = ProgressReader(handler: progress)
                    process.standardOutput = meter?.pipe
                }

                if let askpassScript {
                    var environment = ProcessInfo.processInfo.environment
                    environment["SSH_ASKPASS"] = askpassScript.path
                    environment["SSH_ASKPASS_REQUIRE"] = "force"
                    process.environment = environment
                }

                try cancellation.start()
                // Drain stderr while scp runs so a chatty failure can't fill the pipe.
                var data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let meter {
                    let text = meter.finish()
                    if !text.isEmpty { data = Data(text.utf8) }
                }

                if cancellation.wasCancelled { throw CancellationError() }
                guard process.terminationStatus == 0 else {
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw SSHCopyError.failed(message: message)
                }
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Writes a throwaway shell script that just prints `password` back out
    /// — this is what `SSH_ASKPASS` points `ssh`/`scp`/`ssh-copy-id` at in
    /// place of a real GUI prompt. Lives in its own 0700 directory, deleted
    /// once the operation finishes, so the password sitting on disk briefly
    /// is only ever readable by this user.
    private static func makeAskpassScript(password: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OneRoot-askpass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s' '\(escaped)'\n"
        let scriptURL = directory.appendingPathComponent("askpass.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}

/// Lets a cancelled task stop the child process, whether it has started or not.
private final class ProcessCancellation: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false

    init(_ process: Process) { self.process = process }

    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func start() throws {
        lock.lock()
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { throw CancellationError() }
        try process.run()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if process.isRunning { process.terminate() }
    }
}

/// Reads scp's output through a pipe: progress refreshes go to `handler`,
/// anything else (errors) is kept for the failure message.
private final class ProgressReader: @unchecked Sendable {
    let pipe = Pipe()
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var other: [String] = []

    init(handler: @escaping @Sendable (SSHCopyProgress) -> Void) {
        let handle = pipe.fileHandleForReading
        Thread.detachNewThread { [self] in
            defer { finished.signal() }
            var pending = ""
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                pending += String(decoding: data, as: UTF8.self)
                // The meter redraws one line with carriage returns.
                var pieces = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                pending = pieces.removeLast()
                for piece in pieces { consume(piece, handler) }
            }
            consume(pending, handler)
        }
    }

    private func consume(_ piece: String, _ handler: @Sendable (SSHCopyProgress) -> Void) {
        let text = piece.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let progress = SSHCopyProgress.parse(text) {
            handler(progress)
        } else {
            lock.lock(); other.append(text); lock.unlock()
        }
    }

    /// Waits for the last output and returns the non-progress text.
    func finish() -> String {
        _ = finished.wait(timeout: .now() + 3)
        lock.lock(); defer { lock.unlock() }
        return other.joined(separator: "\n")
    }
}
