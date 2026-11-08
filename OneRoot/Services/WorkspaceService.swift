import Foundation

/// Stores the user's Workspaces as JSON in user defaults.
struct WorkspaceService {
    private static let key = "com.oneroot.workspaces"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Workspace] {
        guard let data = defaults.data(forKey: Self.key),
              let workspaces = try? JSONDecoder().decode([Workspace].self, from: data) else { return [] }
        return workspaces
    }

    func save(_ workspaces: [Workspace]) {
        defaults.set(try? JSONEncoder().encode(workspaces), forKey: Self.key)
    }
}
