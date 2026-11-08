import Foundation

/// Remembers which `FileViewMode` each folder was last shown in. Folders
/// never set default to `.list`, and setting a folder back to `.list`
/// forgets it rather than storing the default — so the stored map only
/// ever holds the folders someone deliberately switched to icons.
struct FolderViewModeService {
    private static let key = "com.oneroot.folderViewModes"
    /// Oldest entries are dropped past this, so years of browsing can't
    /// grow the preferences file without bound.
    static let maxEntries = 500
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mode(for folder: URL) -> FileViewMode {
        load().first { $0.path == Self.key(for: folder) }.flatMap { FileViewMode(rawValue: $0.mode) } ?? .list
    }

    func setMode(_ mode: FileViewMode, for folder: URL) {
        let path = Self.key(for: folder)
        var entries = load().filter { $0.path != path }
        if mode != .list {
            entries.append(Entry(path: path, mode: mode.rawValue)) // newest last
        }
        save(Array(entries.suffix(Self.maxEntries)))
    }

    private struct Entry: Codable {
        let path: String
        let mode: String
    }

    /// Standardized, so `/Users/eric/` and `/Users/eric/./` are one folder.
    private static func key(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }

    private func load() -> [Entry] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
