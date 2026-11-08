import Foundation

enum ArchiveError: LocalizedError {
    case toolNotFound(ArchiveTool)
    case unsupportedFormat(extension: String, tool: ArchiveTool)
    case processFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "Couldn't find \(tool.displayName) on this Mac."
        case .unsupportedFormat(let ext, let tool):
            return "\(tool.displayName) can't extract \".\(ext)\" files."
        case .processFailed(let message):
            return message.isEmpty ? "Archive operation failed." : message
        }
    }
}

/// Compresses/extracts archives by shelling out to whichever engine
/// `ArchiveSettingsService` has selected — the same approach Finder itself
/// uses for "Compress" (it calls `ditto`, not a private API). UI-agnostic;
/// see `SSHCopyService` for the same `Process`-in-`Task.detached` shape.
struct ArchiveService {
    /// Compresses `items` into a single archive inside `directory`, named
    /// `baseName` (auto-numbered on collision, matching
    /// `FileSystemService.uniqueDestination`). `ditto` only ever produces a
    /// zip, regardless of `format`.
    ///
    /// Reports a Finder-style progress popup via `FileOperationProgressCenter`
    /// — indeterminate, since none of the engines print a real completion
    /// percentage for compress.
    func compress(
        _ items: [URL],
        into directory: URL,
        baseName: String,
        tool: ArchiveTool,
        format: ArchiveFormat
    ) async throws -> URL {
        guard let executablePath = tool.executablePath else {
            throw ArchiveError.toolNotFound(tool)
        }
        let effectiveFormat = tool == .appleDitto ? .zip : format
        let destination = FileSystemService.uniqueDestination(
            for: directory.appendingPathComponent("\(baseName).\(effectiveFormat.fileExtension)")
        )

        let title = items.count == 1
            ? "Compressing \u{201C}\(items[0].lastPathComponent)\u{201D}"
            : "Compressing \(items.count) items"
        // A cancelled or failed compress leaves half an archive, which
        // won't open: take it away. It's always a new name of our own
        // (`uniqueDestination`), never something that was there before.
        do {
            try await withProgress(
                title: title,
                totalBytes: 0,
                isIndeterminate: true,
                sourceFolder: Set(items.map { $0.deletingLastPathComponent() }).count == 1 ? items.first?.deletingLastPathComponent() : nil,
                destinationFolder: directory,
                itemCount: items.count
            ) { handle in
                switch tool {
                case .appleDitto:
                    try await compressWithDitto(items, executablePath: executablePath, to: destination, handle: handle)
                case .p7zip:
                    let arguments = ["a", "-t\(effectiveFormat.fileExtension)", destination.path] + items.map(\.path)
                    try await run(executablePath, arguments: arguments, handle: handle)
                case .libarchive:
                    // Each item from its own folder (-C), so it lands at the
                    // archive's root under its own name, as Finder's would.
                    let format = effectiveFormat == .sevenZip ? "7zip" : "zip"
                    let arguments = ["--format", format, "-cf", destination.path]
                        + items.flatMap { ["-C", $0.deletingLastPathComponent().path, $0.lastPathComponent] }
                    try await run(executablePath, arguments: arguments, handle: handle)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// `ditto -c` rejects more than one source outright ("Can't archive
    /// multiple sources"), and wrapping a lone *file* with `--keepParent`
    /// preserves the file's *parent directory's* name rather than the
    /// file's own — neither matches what Finder's own Compress produces.
    /// Staging every item into one throwaway directory and archiving *that*
    /// (without `--keepParent`, so only its contents go in) sidesteps both:
    /// each item lands at the zip's root under its own name, whether it's a
    /// file or a folder, for any number of items — matching Finder exactly.
    private func compressWithDitto(_ items: [URL], executablePath: String, to destination: URL, handle: ProcessHandle) async throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // Through `FileCopier` (a clone on the same APFS volume) with the
        // operation's own flag, so Pause and Cancel reach this step too —
        // with a big selection it can be most of the work.
        for item in items {
            let target = staging.appendingPathComponent(item.lastPathComponent)
            try await Task.detached(priority: .userInitiated) {
                try Platform.copyItem(item, to: target, includeMetadata: true, cancellation: handle.staging) { _ in }
            }.value
        }
        try await run(executablePath, arguments: ["-c", "-k", "--sequesterRsrc", staging.path, destination.path], handle: handle)
    }

    /// Extracts `archiveURL` into a same-named subfolder inside
    /// `directory` — matching Finder's own double-click-to-expand behavior
    /// so a multi-file archive doesn't dump loose items into whatever
    /// folder was chosen. The subfolder name is auto-numbered on collision.
    ///
    /// Reports real progress when possible: `ArchiveSizeInspector` gets the
    /// archive's uncompressed byte total up front (zip only), and a poller
    /// running alongside the extraction process compares the destination
    /// folder's growing size against that total — extraction writes real
    /// uncompressed bytes 1:1, so this is accurate, not an estimate. Falls
    /// back to the same indeterminate treatment as compress for anything
    /// else.
    func extract(_ archiveURL: URL, into directory: URL, tool: ArchiveTool) async throws -> URL {
        guard let executablePath = tool.executablePath else {
            throw ArchiveError.toolNotFound(tool)
        }
        let fileExtension = archiveURL.pathExtension.lowercased()
        guard tool.extractableExtensions.contains(fileExtension) else {
            throw ArchiveError.unsupportedFormat(extension: fileExtension, tool: tool)
        }

        let destination = Self.uniqueDirectory(
            for: directory.appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let arguments: [String]
        switch tool {
        case .appleDitto:
            arguments = ["-x", "-k", archiveURL.path, destination.path]
        case .p7zip:
            arguments = ["x", archiveURL.path, "-o\(destination.path)", "-aoa"]
        case .libarchive:
            arguments = ["-xf", archiveURL.path, "-C", destination.path]
        }

        let title = "Extracting \u{201C}\(archiveURL.lastPathComponent)\u{201D}"
        let totalBytes = await ArchiveSizeInspector().totalUncompressedSize(of: archiveURL) ?? 0

        // Same for a cancelled or failed extract: the folder it was filling
        // is new (`uniqueDirectory`) and only half there.
        do {
            try await withProgress(
                title: title,
                totalBytes: totalBytes,
                isIndeterminate: totalBytes == 0,
                sourceFolder: archiveURL.deletingLastPathComponent(),
                destinationFolder: destination
            ) { handle in
                guard totalBytes > 0 else {
                    try await run(executablePath, arguments: arguments, handle: handle)
                    return
                }
                try await self.runWithSizePolling(
                    executablePath, arguments: arguments, handle: handle,
                    destination: destination, totalBytes: totalBytes
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// Runs `run(...)` alongside a poller that samples `destination`'s
    /// growing size every 250ms and reports it as progress, stopping the
    /// poller as soon as extraction finishes (success or failure).
    private func runWithSizePolling(
        _ executablePath: String,
        arguments: [String],
        handle: ProcessHandle,
        destination: URL,
        totalBytes: Int64
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.run(executablePath, arguments: arguments, handle: handle) }
            group.addTask {
                let fileSystemService = FileSystemService()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    let currentSize = await fileSystemService.totalSize(of: [destination])
                    await Platform.progress.update(handle.progressID, completedBytes: min(currentSize, totalBytes))
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        await Platform.progress.update(handle.progressID, completedBytes: totalBytes)
    }

    /// Directory-appropriate sibling of `FileSystemService.uniqueDestination`:
    /// appends " (2)", " (3)", … to the *whole* folder name instead of
    /// splitting around a dot. A folder named after an archive like
    /// "notes.txt" isn't a file with a ".txt" extension to preserve — that
    /// helper would otherwise turn it into "notes (2).txt".
    private static func uniqueDirectory(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        var counter = 2
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) (\(counter))", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    /// Registers a `FileOperationProgressCenter` entry for the duration of
    /// `body`, giving it a `ProcessHandle` whose cancel button both
    /// terminates whatever `Process` `run()` creates and marks the
    /// operation as user-cancelled — `body`'s failure is rethrown as
    /// `CancellationError` in that case instead of `ArchiveError
    /// .processFailed`, so callers can tell "you clicked Cancel" apart from
    /// a genuine failure without inspecting stderr text.
    private func withProgress(
        title: String,
        totalBytes: Int64,
        isIndeterminate: Bool,
        sourceFolder: URL? = nil,
        destinationFolder: URL? = nil,
        itemCount: Int = 1,
        _ body: (ProcessHandle) async throws -> Void
    ) async throws {
        let handle = ProcessHandle()
        handle.progressID = await Platform.progress.begin(
            title: title,
            symbolName: "archivebox.fill",
            totalBytes: totalBytes,
            isIndeterminate: isIndeterminate,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            itemCount: itemCount,
            pauseControl: handle,
            cancel: { handle.cancel() }
        )

        // Not a plain `defer` — `defer` bodies run synchronously and can't
        // `await`, so wrapping the cleanup in `Task { await ... }` there
        // would only *schedule* it, with no guarantee it's actually run by
        // the time this function returns. Awaiting `finish` directly on
        // both paths instead means the popup is provably gone (not just
        // "probably about to close") before a caller sees this return.
        do {
            try await body(handle)
            await Platform.progress.finish(handle.progressID)
        } catch {
            // No Retry: compressing or extracting again starts from scratch,
            // which the user can do just as well from the item.
            let outcome: FileOperationOutcome = handle.wasCancelled || error is CancellationError
                ? .cancelled
                : .failure(error, finished: 0, of: 1)
            await Platform.progress.finish(handle.progressID, outcome: outcome)
            throw handle.wasCancelled ? CancellationError() : error
        }
    }

    private func run(_ executablePath: String, arguments: [String], handle: ProcessHandle) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice

            try process.run()
            // Tracked only while actually running, not for the whole
            // `Task.detached` body — `ArchiveProcessRegistry` exists so
            // quitting mid-operation can find and kill this exact process;
            // once it's exited there's nothing left to kill.
            ArchiveProcessRegistry.shared.register(process)
            handle.attach(process)
            defer { ArchiveProcessRegistry.shared.unregister(process) }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw ArchiveError.processFailed(message: message)
            }
        }.value
    }
}

/// Lets a `FileOperationProgress`'s cancel button reach whichever `Process`
/// `ArchiveService.run` ends up creating (not known yet when the progress
/// entry is registered) and records that the resulting failure was
/// user-requested — see `ArchiveService.withProgress`.
///
/// Pausing stops the process outright (SIGSTOP) and resuming continues it
/// (SIGCONT), so `ditto`/`7z` carry on exactly where they were.
private final class ProcessHandle: PauseControl, @unchecked Sendable {
    var progressID = UUID()
    /// For the copying a compress does before its process starts (see
    /// `compressWithDitto`).
    let staging = CancellationFlag()

    private let lock = NSLock()
    private var process: Process?
    private var isPaused = false
    private(set) var wasCancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let paused = isPaused
        lock.unlock()
        // Paused before this step's process started: it starts paused too.
        if paused { kill(process.processIdentifier, SIGSTOP) }
    }

    func pause() {
        staging.pause()
        lock.lock()
        isPaused = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { kill(process.processIdentifier, SIGSTOP) }
    }

    func resume() {
        staging.resume()
        lock.lock()
        isPaused = false
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { kill(process.processIdentifier, SIGCONT) }
    }

    func cancel() {
        staging.cancel()
        lock.lock()
        wasCancelled = true
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        // A stopped process doesn't act on SIGTERM until it's continued.
        kill(process.processIdentifier, SIGCONT)
        process.terminate()
    }
}
