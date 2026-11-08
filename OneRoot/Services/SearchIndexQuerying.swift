import Foundation

/// A searchable file index — Spotlight in production, a fake in tests.
protocol SearchIndexQuerying {
    /// Paths of indexed items under `root` matching `query`, or `nil` when
    /// `root` isn't indexed (or the query couldn't run), meaning the caller
    /// should fall back to walking the tree itself.
    func paths(matching query: String, under root: URL) -> [String]?
}

/// Items Spotlight says were opened recently, with when — Recents.
protocol RecentItemsQuerying: Sendable {
    /// Every item under `roots` with a last-used date in the last `days`
    /// days, with that date (Spotlight's `kMDItemLastUsedDate`, which only
    /// changes when an item is opened — unlike the file's access time,
    /// which anything reading it bumps).
    func recentlyUsed(withinDays days: Int, under roots: [URL]) -> [(path: String, lastUsed: Date)]
}
