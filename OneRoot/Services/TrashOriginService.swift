import Foundation

/// Remembers where a trashed item came from, keyed by its current location
/// in Trash. macOS records no such mapping anywhere a third-party app can
/// read — Finder's own "Put Back" relies on private, Finder-only
/// bookkeeping — so Restore only works reliably for items OneRoot itself
/// moved to Trash. Persisted (not just in-memory) so it survives a relaunch.
struct TrashOriginService {
    private static let key = "com.oneroot.trashOrigins"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordOrigin(trashedURL: URL, originalURL: URL) {
        var map = load()
        map[trashedURL.path] = originalURL.path
        save(map)
    }

    /// OneRoot's own record, or the system's where it keeps one (Linux's
    /// .trashinfo files, which other apps write too).
    func originalLocation(forTrashedURL url: URL) -> URL? {
        load()[url.path].map { URL(fileURLWithPath: $0) } ?? Platform.trashedItemOrigin(url)
    }

    func removeRecord(forTrashedURL url: URL) {
        Platform.forgetTrashedItem(url)
        var map = load()
        guard map.removeValue(forKey: url.path) != nil else { return }
        save(map)
    }

    private func load() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    private func save(_ map: [String: String]) {
        defaults.set(map, forKey: Self.key)
    }
}
