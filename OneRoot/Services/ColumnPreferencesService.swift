import Foundation

/// Persists which file-list columns the user has chosen to show, and in
/// what order. Not sandboxed, so plain raw-value strings in `UserDefaults`
/// are enough — no security-scoped bookmarks needed.
struct ColumnPreferencesService {
    private static let key = "com.oneroot.visibleColumns"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Falls back to `FileColumn.defaultVisible` the first time the app
    /// runs (nothing saved yet) or if saved data is stale/corrupt.
    func load() -> [FileColumn] {
        guard let rawValues = defaults.array(forKey: Self.key) as? [String] else {
            return FileColumn.defaultVisible
        }
        let columns = rawValues.compactMap(FileColumn.init(rawValue:))
        return columns.isEmpty ? FileColumn.defaultVisible : FileColumn.normalized(columns)
    }

    func save(_ columns: [FileColumn]) {
        defaults.set(columns.map(\.rawValue), forKey: Self.key)
    }
}
