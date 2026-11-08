import Foundation

/// Reads free/total space for the volume containing a given URL — backs
/// the status bar's space indicator. A `resourceValues` stat can block on a
/// slow or network volume, so it runs off the main actor like every other
/// filesystem call in the service layer (see CLAUDE.md's main-thread-stall
/// gotcha).
struct VolumeSpaceService {
    func space(for url: URL) async -> VolumeSpace? {
        await Task.detached(priority: .utility) {
            guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
                  let available = values.volumeAvailableCapacity,
                  let total = values.volumeTotalCapacity
            else { return nil }
            return VolumeSpace(availableCapacity: Int64(available), totalCapacity: Int64(total))
        }.value
    }

    /// The volume's display name ("Macintosh HD"), read off the main actor
    /// like the space.
    func volumeName(for url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName
        }.value
    }
}
