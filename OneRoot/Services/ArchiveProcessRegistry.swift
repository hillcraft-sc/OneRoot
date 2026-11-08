import Foundation

/// Tracks every `Process` currently running an `ArchiveService` compress or
/// extract — a subprocess like `ditto`/`7z` isn't tied to OneRoot's own
/// lifetime; quitting the app leaves it running in the background
/// (reparented, not killed) unless something explicitly terminates it
/// first. `AppDelegate.applicationShouldTerminate` consults this to warn
/// before quitting, and to actually stop the process if the user confirms.
///
/// A plain shared instance rather than DI through `ArchiveService`/
/// `FileListViewModel`: this needs to be visible app-wide (every tab, every
/// window), not scoped to whichever view model happened to start the
/// operation — the same reason `ColumnPreferencesStore`/
/// `HiddenFilesPreferenceStore` are shared singletons too.
final class ArchiveProcessRegistry: @unchecked Sendable {
    static let shared = ArchiveProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    private init() {}

    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = process
    }

    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    var hasRunningProcesses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !processes.isEmpty
    }

    /// Sends SIGTERM to every tracked process — best-effort, not a wait for
    /// them to actually exit (the app is quitting either way).
    func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()
        for process in running where process.isRunning {
            // A paused (stopped) process only acts on SIGTERM once continued.
            kill(process.processIdentifier, SIGCONT)
            process.terminate()
        }
    }
}
