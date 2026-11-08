import Foundation

/// Persists the sidebar's user-pinned folders. Not sandboxed, so plain paths
/// in `UserDefaults` are enough — no security-scoped bookmarks needed.
struct PinnedLocationsService {
    private static let key = "com.oneroot.pinnedLocations"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [URL] {
        (defaults.array(forKey: Self.key) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    func save(_ urls: [URL]) {
        defaults.set(urls.map(\.path), forKey: Self.key)
    }
}
