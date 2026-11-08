import Foundation

/// Persists which editor app the pinned "Editor" entry in a folder's Open
/// With menu launches — see `openInEditor`. `nil` means "not configured,"
/// which hides that entry entirely; unlike `TerminalPreferenceService`
/// there's no universal default to fall back to (there's no macOS-bundled
/// editor the way Terminal.app is always present).
struct EditorPreferenceService {
    private static let bundleIdentifierKey = "com.oneroot.editorAppBundleIdentifier"
    private static let workingDirectoryFlagKey = "com.oneroot.editorAppWorkingDirectoryFlag"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bundleIdentifier() -> String? {
        defaults.string(forKey: Self.bundleIdentifierKey)
    }

    func setBundleIdentifier(_ bundleIdentifier: String?) {
        guard let bundleIdentifier else {
            defaults.removeObject(forKey: Self.bundleIdentifierKey)
            return
        }
        defaults.set(bundleIdentifier, forKey: Self.bundleIdentifierKey)
    }

    /// A command-line flag/subcommand some editors need to open a given
    /// folder instead of just launching — most (VS Code and Zed included)
    /// don't need this: `nil` means "use the plain document-open
    /// mechanism," which works even for an editor that doesn't declare
    /// folder support in its own `Info.plist` (see `openInEditor`).
    func workingDirectoryFlag() -> String? {
        defaults.string(forKey: Self.workingDirectoryFlagKey)
    }

    func setWorkingDirectoryFlag(_ flag: String?) {
        guard let flag, !flag.isEmpty else {
            defaults.removeObject(forKey: Self.workingDirectoryFlagKey)
            return
        }
        defaults.set(flag, forKey: Self.workingDirectoryFlagKey)
    }
}
