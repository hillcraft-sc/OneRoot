import Foundation

/// Persists the app-wide navigation/browsing history — the folders the
/// user has visited, most-recent first — plus how many of them to keep.
///
/// Distinct from `PinnedLocationsService`: pins are a small curated set the
/// user maintains by hand and that never changes on its own; this is an
/// automatic, capped log of everywhere they've browsed. Not sandboxed, so
/// plain paths in `UserDefaults` are enough — no security-scoped bookmarks.
struct NavigationHistoryService {
    private static let entriesKey = "com.oneroot.navigationHistory"
    private static let limitKey = "com.oneroot.navigationHistoryLimit"

    /// Used when the user has never set a limit, and the value the Settings
    /// stepper starts at.
    static let defaultLimit = 20
    /// Guard-rails for the Settings stepper and for anything read back from
    /// `UserDefaults` (a hand-edited or corrupt value shouldn't be able to
    /// make the history unbounded or zero-length). The Go menu only ever
    /// shows the most recent handful; the rest is browsable in the History
    /// window, so this can be generous.
    static let limitRange = 5...200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadEntries() -> [URL] {
        (defaults.array(forKey: Self.entriesKey) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    func saveEntries(_ urls: [URL]) {
        defaults.set(urls.map(\.path), forKey: Self.entriesKey)
    }

    /// An unset key (or a nonsense stored value) reads back as
    /// `defaultLimit`, so no `UserDefaults.register(defaults:)` is needed.
    var limit: Int {
        guard defaults.object(forKey: Self.limitKey) != nil else { return Self.defaultLimit }
        return Self.clamp(defaults.integer(forKey: Self.limitKey))
    }

    func saveLimit(_ limit: Int) {
        defaults.set(Self.clamp(limit), forKey: Self.limitKey)
    }

    static func clamp(_ value: Int) -> Int {
        min(max(value, limitRange.lowerBound), limitRange.upperBound)
    }
}
