import Foundation

/// Persists the "Saved Destinations" list shown in Copy via SSH and managed
/// in Settings. Not sandboxed, so a JSON blob in `UserDefaults` is enough —
/// mirrors `SavedServersService`'s approach for SMB favorites. Never stores
/// passwords/passphrases; those live in the Keychain via
/// `SSHCredentialsService`, keyed by each destination's `id`.
struct SavedSSHDestinationsService {
    private static let key = "com.oneroot.savedSSHDestinations"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedSSHDestination] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SavedSSHDestination].self, from: data)) ?? []
    }

    func save(_ destinations: [SavedSSHDestination]) {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Adds `destination`, or replaces the existing one with the same `id`.
    /// Returns the updated list.
    @discardableResult
    func upsert(_ destination: SavedSSHDestination) -> [SavedSSHDestination] {
        var destinations = load()
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations[index] = destination
        } else {
            destinations.append(destination)
        }
        save(destinations)
        return destinations
    }

    /// Removes the destination with the given id. Returns the updated list.
    @discardableResult
    func remove(id: SavedSSHDestination.ID) -> [SavedSSHDestination] {
        var destinations = load()
        destinations.removeAll { $0.id == id }
        save(destinations)
        return destinations
    }
}
