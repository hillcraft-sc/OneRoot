import Foundation

/// Persists whether the file list shows hidden (dot-prefixed) files.
/// Not sandboxed, so a plain `Bool` in `UserDefaults` is enough.
struct HiddenFilesPreferenceService {
    private static let key = "com.oneroot.showHiddenFiles"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func save(_ showHiddenFiles: Bool) {
        defaults.set(showHiddenFiles, forKey: Self.key)
    }
}
