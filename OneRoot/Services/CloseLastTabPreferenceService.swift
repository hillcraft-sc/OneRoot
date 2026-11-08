import Foundation

/// Persists whether closing a window's last tab (⌘W, or the tab bar's own
/// close button) should ask for confirmation first — see
/// `CloseLastTabConfirmation`. Stored as "suppress" rather than "warn" so an
/// unset default (`false`) means the warning is still on, matching the
/// out-of-the-box behavior, without needing `UserDefaults.register(defaults:)`.
struct CloseLastTabPreferenceService {
    private static let key = "com.oneroot.suppressCloseLastTabWarning"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldWarn: Bool {
        !defaults.bool(forKey: Self.key)
    }

    func setShouldWarn(_ shouldWarn: Bool) {
        defaults.set(!shouldWarn, forKey: Self.key)
    }
}
