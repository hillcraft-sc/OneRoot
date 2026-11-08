import Foundation

/// Persists which terminal app "Open in Terminal" should use, by bundle
/// identifier — survives the app being moved, and is how macOS itself
/// prefers to resolve apps. `nil` means "use the default: Terminal.app,
/// opened the same way it always has been." Resolving a bundle identifier
/// to an app URL is an `NSWorkspace`/AppKit concern, so it happens at the
/// call site (`OpenInTerminal.swift`), not here — this service stays
/// Foundation-only per CLAUDE.md §1.
struct TerminalPreferenceService {
    private static let bundleIdentifierKey = "com.oneroot.terminalAppBundleIdentifier"
    private static let workingDirectoryFlagKey = "com.oneroot.terminalAppWorkingDirectoryFlag"
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

    /// A command-line flag (e.g. `--working-directory`) some terminal
    /// apps need to open at a given folder instead of just launching —
    /// they don't implement macOS's normal "open this app with a folder"
    /// document-open convention the way Terminal.app/iTerm2 do. `nil`
    /// means "use the plain document-open mechanism," which is correct
    /// for apps that *do* support it.
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
