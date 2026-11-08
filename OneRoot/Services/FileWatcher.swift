#if os(macOS)
import CoreServices
import Foundation

/// Watches one or more directories (recursively — FSEvents has no
/// non-recursive mode) for external changes and calls `onChange`
/// (debounced) whenever something changes. UI-agnostic — no SwiftUI/AppKit
/// imports. The Mac's `FileWatching`.
final class FileWatcher: FileWatching {
    private var stream: FSEventStreamRef?
    private var pendingPaths: Set<String> = []
    private var pendingSignal: DispatchWorkItem?

    var onChange: (@MainActor () -> Void)?

    /// Coalesces bursts of individual file events (e.g. a large copy) into a
    /// single refresh, per CLAUDE.md's FSEvents gotcha: 300 ms after the
    /// last event. Runs on the main queue, where the stream delivers.
    private func signal() {
        pendingSignal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pendingSignal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The paths that changed since the last call, then clears them. One
    /// `onChange` stands for a whole burst, so callers that need to know
    /// exactly what changed read the accumulated set here.
    func drainChangedPaths() -> Set<String> {
        defer { pendingPaths.removeAll() }
        return pendingPaths
    }

    /// Starts watching `urls`, replacing any previous watch.
    func watch(_ urls: [URL]) {
        stop()
        guard !urls.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            if let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] {
                watcher.pendingPaths.formUnion(paths)
            }
            watcher.signal()
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            urls.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    func stop() {
        pendingSignal?.cancel()
        pendingSignal = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
#endif
