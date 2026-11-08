import Foundation

/// Persists whether "Copy via SSH" requires Touch ID/password first (see
/// `DeviceAuthenticationService`). Not sandboxed, so a plain `Bool` in
/// `UserDefaults` is enough — mirrors `HiddenFilesPreferenceService`'s
/// approach, except this one defaults to *on*, so `object(forKey:)` is used
/// instead of `bool(forKey:)` to tell "never set" apart from "explicitly
/// turned off."
struct SSHDeviceAuthenticationPreferenceService {
    private static let key = "com.oneroot.requireDeviceAuthenticationForSSHCopy"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled() -> Bool {
        defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}
