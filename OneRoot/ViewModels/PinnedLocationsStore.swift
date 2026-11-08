import Foundation
import Observation

/// The user's pinned folders, shared by everything that shows or changes
/// them: the destination sidebar lists them, while the folder hierarchy's
/// context menu pins/unpins and trashing a pinned folder unpins it. Same
/// app-wide pattern as `ColumnPreferencesStore`, so a pin made in one
/// window shows up in every other immediately.
@MainActor
@Observable
final class PinnedLocationsStore {
    static let shared = PinnedLocationsStore()

    private(set) var urls: [URL]

    private let service: PinnedLocationsService

    init(service: PinnedLocationsService = PinnedLocationsService()) {
        self.service = service
        self.urls = service.load()
    }

    /// Compared by path, so `/x/` (how a folder's URL often reads) and
    /// `/x` count as the same pin.
    func isPinned(_ url: URL) -> Bool {
        urls.contains { Self.samePath($0, url) }
    }

    func toggle(_ url: URL) {
        if isPinned(url) {
            unpin(url)
        } else {
            urls.append(url)
            service.save(urls)
        }
    }

    func unpin(_ url: URL) {
        guard let index = urls.firstIndex(where: { Self.samePath($0, url) }) else { return }
        urls.remove(at: index)
        service.save(urls)
    }

    private static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }
}
