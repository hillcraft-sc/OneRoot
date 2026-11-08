import Foundation

/// Discovers cloud-storage provider mounts (Nextcloud, Google Drive, Dropbox,
/// Box, etc.) that macOS surfaces through File Provider extensions rather
/// than as classic mounted volumes — they never appear in
/// `FileManager.mountedVolumeURLs`. Finder shows these under its sidebar's
/// "Locations" section by scanning this same folder, so we do the same.
///
/// iCloud Drive is a separate case: it predates the `~/Library/CloudStorage`
/// convention third-party providers use, so it lives at its own
/// differently-named legacy path and would otherwise never be found here.
/// It's existence-checked (not everyone has iCloud Drive enabled) rather
/// than assumed present, unlike `/Applications`/home in `DestinationsViewModel`.
struct CloudStorageLocationsService {
    private let cloudStorageDirectory: URL
    private let iCloudDriveURL: URL

    init(
        cloudStorageDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage"),
        iCloudDriveURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    ) {
        self.cloudStorageDirectory = cloudStorageDirectory
        self.iCloudDriveURL = iCloudDriveURL
    }

    func discover() -> [URL] {
        var locations = discoverProviderMounts()
        if FileManager.default.fileExists(atPath: iCloudDriveURL.path) {
            locations.append(iCloudDriveURL)
        }
        return locations
    }

    private func discoverProviderMounts() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: cloudStorageDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return (contents ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
    }
}
