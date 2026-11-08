import Foundation

/// Persists which theme is chosen: `ThemeCatalog.automaticChoiceID` (follow
/// macOS) or a theme's id. A stored id that no longer exists (a theme
/// removed in a later version) quietly falls back to Automatic.
struct ThemePreferenceService {
    private static let key = "com.oneroot.theme"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func choiceID() -> String {
        guard let stored = defaults.string(forKey: Self.key),
              ThemeCatalog.isValidChoice(stored) else {
            return ThemeCatalog.automaticChoiceID
        }
        return stored
    }

    func setChoiceID(_ id: String) {
        defaults.set(id, forKey: Self.key)
    }

    private static let defaultsVersionKey = "com.oneroot.themeDefaultsVersion"

    /// Once per install: switches to the OneRoot look (Automatic), the new
    /// default, whatever was chosen before it existed. The earlier themes
    /// stay a click away in Settings ▸ Appearance; a choice made after this
    /// is left alone.
    func adoptOneRootDefaultIfNeeded() {
        guard defaults.integer(forKey: Self.defaultsVersionKey) < 2 else { return }
        defaults.set(ThemeCatalog.automaticChoiceID, forKey: Self.key)
        defaults.set(2, forKey: Self.defaultsVersionKey)
    }
}
