#if os(macOS)
import AppKit
import Foundation

/// Enumerates mounted volumes and publishes live updates as drives are
/// plugged in, ejected, or renamed.
///
/// This imports AppKit for `NSWorkspace`, which is the system-level facade
/// for volume notifications and ejecting — there's no Foundation-only
/// equivalent. It does no view rendering and needs no window, so it stays
/// within the spirit of "services don't touch UI" even though the framework
/// name is AppKit (see SPEC.md §5.2).
final class VolumeService: VolumeProviding {
    private static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeAvailableCapacityKey,
        .volumeTotalCapacityKey,
        .volumeIsLocalKey,
    ]

    /// Reports the current volume list right away, then again whenever a
    /// volume mounts, unmounts, or is renamed — until the returned token is
    /// released.
    ///
    /// `currentVolumes()` fetches resource values for every mounted volume,
    /// including network ones — the first touch of a network volume can
    /// block on a TCC consent prompt. So the list is read on a background
    /// queue (a serial one, so updates arrive in order), and a slow or stuck
    /// prompt doesn't freeze the whole app (see CLAUDE.md's main-thread-stall
    /// gotcha).
    func monitorVolumes(_ onChange: @escaping @MainActor ([VolumeInfo]) -> Void) -> AnyObject {
        let queue = DispatchQueue(label: "com.oneroot.volumes", qos: .userInitiated)
        let report = {
            queue.async {
                let volumes = Self.currentVolumes()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onChange(volumes) }
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification]
        let observers = names.map { center.addObserver(forName: $0, object: nil, queue: nil) { _ in report() } }
        report()
        return NotificationObservers(observers, center: center)
    }

    @discardableResult
    func eject(_ volume: VolumeInfo) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            return true
        } catch {
            return false
        }
    }

    static func currentVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls
            .map(makeVolumeInfo)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func makeVolumeInfo(for url: URL) -> VolumeInfo {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        return VolumeInfo(
            url: url,
            name: values?.volumeName ?? url.lastPathComponent,
            isRemovable: values?.volumeIsRemovable ?? false,
            isEjectable: values?.volumeIsEjectable ?? false,
            availableCapacity: values?.volumeAvailableCapacity.map(Int64.init),
            totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
            isLocal: values?.volumeIsLocal ?? true
        )
    }
}
#endif
