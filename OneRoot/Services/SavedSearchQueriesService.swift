import Foundation

/// Persists the "Saved Queries" list in Advanced Search — mirrors
/// `SavedSSHDestinationsService`'s approach: a JSON blob in `UserDefaults`
/// is enough since the app isn't sandboxed.
struct SavedSearchQueriesService {
    private static let key = "com.oneroot.savedSearchQueries"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedSearchQuery] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SavedSearchQuery].self, from: data)) ?? []
    }

    func save(_ queries: [SavedSearchQuery]) {
        guard let data = try? JSONEncoder().encode(queries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Adds `query`, or replaces the existing one with the same `id`.
    /// Returns the updated list.
    @discardableResult
    func upsert(_ query: SavedSearchQuery) -> [SavedSearchQuery] {
        var queries = load()
        if let index = queries.firstIndex(where: { $0.id == query.id }) {
            queries[index] = query
        } else {
            queries.append(query)
        }
        save(queries)
        return queries
    }

    /// Removes the query with the given id. Returns the updated list.
    @discardableResult
    func remove(id: SavedSearchQuery.ID) -> [SavedSearchQuery] {
        var queries = load()
        queries.removeAll { $0.id == id }
        save(queries)
        return queries
    }
}
