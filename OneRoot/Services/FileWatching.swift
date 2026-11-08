import Foundation

/// Tells a view model when something changed inside the folders it shows.
/// FSEvents on the Mac (`FileWatcher`); inotify on Linux in phase 4 (#81).
protocol FileWatching: AnyObject {
    /// Called on the main actor once per burst of changes — a large copy
    /// is one call, not thousands. Ask `drainChangedPaths()` what changed.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Starts watching `urls` (and everything below them), replacing any
    /// previous watch.
    func watch(_ urls: [URL])
    /// The paths that changed since the last call, then clears them.
    func drainChangedPaths() -> Set<String>
    /// Stops watching (a pending `onChange` included).
    func stop()
}

/// Does nothing — the default for view models that take a `FileWatching`,
/// so tests that don't care about live updates aren't each starting a real
/// watcher (across a full test run, that contention made the tests that
/// *do* care flaky). Real call sites (`MainWindowView`, `WindowViewModel`)
/// inject an actual watcher explicitly.
final class NullFileWatcher: FileWatching {
    var onChange: (@MainActor () -> Void)?
    init() {}
    func watch(_ urls: [URL]) {}
    func drainChangedPaths() -> Set<String> { [] }
    func stop() {}
}
