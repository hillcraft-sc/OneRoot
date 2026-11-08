import Foundation

/// Settings ▸ General ▸ "Copy to the same disk one at a time": copies and
/// moves that carry data between disks wait for any earlier one that uses
/// one of the same disks, so two big copies don't fight over a drive (which
/// makes both slower, and a spinning or network disk much slower). Work on
/// unrelated disks still runs side by side, and a move or copy within one
/// disk (a rename or an APFS clone) never waits.
///
/// First come, first served. A waiting operation can be told to start now.
actor FileTransferQueue {
    static let shared = FileTransferQueue()
    static let enabledKey = "com.oneroot.fileOperations.oneAtATime"

    /// On unless turned off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private struct Entry {
        let id: UUID
        let disks: Set<String>
        var isRunning: Bool
    }

    private var entries: [Entry] = []

    /// Joins the line and returns once it may run: no earlier entry shares
    /// a disk. Polls, so Cancel and Start Now (checked by `shouldStop` /
    /// `startNow`) take effect within a moment. Throws `CancellationError`
    /// when `shouldStop` turns true while waiting (the entry is removed).
    /// `onWaiting` is called once if it has to wait at all.
    func acquire(
        id: UUID,
        disks: Set<String>,
        shouldStop: @Sendable () -> Bool,
        startNow: @Sendable () -> Bool,
        onWaiting: @Sendable () async -> Void
    ) async throws {
        entries.append(Entry(id: id, disks: disks, isRunning: false))
        var toldWaiting = false
        while true {
            if shouldStop() {
                release(id: id)
                throw CancellationError()
            }
            if startNow() || mayRun(id) {
                if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].isRunning = true }
                return
            }
            if !toldWaiting {
                toldWaiting = true
                await onWaiting()
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func release(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Whether nothing ahead of `id` in line uses one of its disks.
    private func mayRun(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return true }
        let disks = entries[index].disks
        return !entries[..<index].contains { !$0.disks.isDisjoint(with: disks) }
    }

    /// For tests.
    var count: Int { entries.count }

    /// The disk (volume) a file is on, as a comparable key — its mount
    /// point's path. `nil` when it can't be told.
    static func disk(of url: URL) -> String? {
        var probe = url
        // A destination item may not exist yet: ask its nearest existing folder.
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        return (try? probe.resourceValues(forKeys: [.volumeURLKey]).volume)?.path
    }

    /// The disks an operation moving data from `sources` into
    /// `destination` uses — empty when everything is on the destination's
    /// own disk, where no data has to move.
    static func disks(for sources: [URL], into destination: URL) -> Set<String> {
        guard let target = disk(of: destination) else { return [] }
        let others = Set(sources.compactMap(disk(of:))).subtracting([target])
        return others.isEmpty ? [] : others.union([target])
    }
}

/// Start Now, pressed on an operation waiting in `FileTransferQueue`.
final class StartNowFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
