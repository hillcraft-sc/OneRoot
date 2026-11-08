import Foundation

/// Persists the "Favorite Servers" list shown in Connect to Server. Not
/// sandboxed, so a JSON blob in `UserDefaults` is enough — mirrors
/// `PinnedLocationsService`'s approach for the sidebar's pinned folders.
struct SavedServersService {
    private static let key = "com.oneroot.savedServers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedServer] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SavedServer].self, from: data)) ?? []
    }

    func save(_ servers: [SavedServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Adds `server`, ignoring it if a favorite with the same URL already
    /// exists. Returns the updated list.
    @discardableResult
    func add(_ server: SavedServer) -> [SavedServer] {
        var servers = load()
        guard !servers.contains(where: { $0.url == server.url }) else { return servers }
        servers.append(server)
        save(servers)
        return servers
    }

    /// Removes the favorite with the given id. Returns the updated list.
    @discardableResult
    func remove(id: SavedServer.ID) -> [SavedServer] {
        var servers = load()
        servers.removeAll { $0.id == id }
        save(servers)
        return servers
    }
}
