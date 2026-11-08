import Foundation

/// The mounted volumes, kept current. `NSWorkspace` on the Mac
/// (`VolumeService`); /proc/self/mountinfo and udisks2 on Linux in phase 4
/// (#81).
protocol VolumeProviding {
    /// Calls `onChange` on the main actor with the current volumes right
    /// away, then again whenever one mounts, unmounts, or is renamed — for
    /// as long as the returned token is kept.
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject
    @discardableResult func eject(_ volume: VolumeInfo) -> Bool
    /// What the last failed `eject` reported (the unmount tool's own words), if known.
    func lastEjectFailure() -> String?
}

extension VolumeProviding {
    func lastEjectFailure() -> String? { nil }
}

/// Keeps `NotificationCenter` observers registered while it's alive, and
/// removes them when it's released — the token a monitor hands back.
final class NotificationObservers {
    private let observers: [NSObjectProtocol]
    private let center: NotificationCenter

    init(_ observers: [NSObjectProtocol], center: NotificationCenter = .default) {
        self.observers = observers
        self.center = center
    }

    deinit {
        observers.forEach(center.removeObserver)
    }
}
