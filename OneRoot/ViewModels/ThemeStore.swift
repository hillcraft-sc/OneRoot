import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// The app-wide current theme, observed by every window. `.shared` is the
/// one real instance; tests build their own with a fake system appearance.
///
/// Choosing Automatic follows macOS: `current` becomes `oneRootLight` or
/// `oneRootDark` (or, for macOS Automatic, `nativeLight`/`nativeDark`) and
/// flips when the system appearance does. Choosing any
/// other theme pins the whole app to that theme's light/dark appearance
/// (`NSApp.appearance`), so everything the theme doesn't paint itself —
/// scrollbars, menus, text cursors, system controls — matches it.
///
/// On Linux there's no AppKit: the app passes `systemIsDark` and
/// `applyAppearance` (libadwaita's style manager) and calls
/// `systemAppearanceChanged()` when the desktop's scheme changes.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// What's chosen in Settings: `ThemeCatalog.automaticChoiceID` or a theme id.
    private(set) var choiceID: String
    /// What's actually in effect — `choiceID` resolved.
    private(set) var current: Theme

    private let preferences: ThemePreferenceService
    private let systemIsDark: () -> Bool
    /// `true`/`false` pins the app to dark/light; `nil` follows macOS.
    private let applyAppearance: (Bool?) -> Void
    #if os(macOS)
    @ObservationIgnored private var systemAppearanceObservation: NSKeyValueObservation?
    #endif
    /// True while `resolve` is changing the app's appearance. Setting it
    /// makes macOS report an appearance change, which lands back in
    /// `systemAppearanceChanged` — from inside `resolve` — and, with
    /// Automatic chosen, would resolve again, set it again, and so on until
    /// the stack overflowed (choosing Automatic used to crash the app).
    private var isResolving = false

    init(
        preferences: ThemePreferenceService = ThemePreferenceService(),
        systemIsDark: @escaping () -> Bool = ThemeStore.currentSystemIsDark,
        applyAppearance: @escaping (Bool?) -> Void = ThemeStore.applyToApp,
        observesSystemAppearance: Bool = true
    ) {
        self.preferences = preferences
        self.systemIsDark = systemIsDark
        self.applyAppearance = applyAppearance
        preferences.adoptOneRootDefaultIfNeeded()
        let id = preferences.choiceID()
        choiceID = id
        current = ThemeCatalog.nativeDark // placeholder; resolved just below
        resolve(id)
        #if os(macOS)
        if observesSystemAppearance {
            // Fires when macOS switches between light and dark — and also
            // when this store pins the appearance itself, which `resolve`
            // ignores unless Automatic is chosen.
            systemAppearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.systemAppearanceChanged() }
            }
        }
        #endif
    }

    func choose(_ id: String) {
        guard ThemeCatalog.isValidChoice(id) else { return }
        preferences.setChoiceID(id)
        choiceID = id
        resolve(id)
    }

    /// For Automatic, re-reads the system appearance.
    func systemAppearanceChanged() {
        guard !isResolving, ThemeCatalog.automaticPair(for: choiceID) != nil else { return }
        resolve(choiceID)
    }

    private func resolve(_ id: String) {
        isResolving = true
        defer { isResolving = false }
        let resolved: Theme
        if let pair = ThemeCatalog.automaticPair(for: id) {
            // Follow the system first, then read it — while pinned, the
            // app's own appearance is the pinned one, not the system's.
            applyAppearance(nil)
            resolved = systemIsDark() ? pair.dark : pair.light
        } else {
            resolved = ThemeCatalog.theme(withID: id) ?? ThemeCatalog.nativeDark
            applyAppearance(resolved.isDark)
        }
        if current != resolved { current = resolved }
    }

    // MARK: Real system hooks

    #if os(macOS)
    nonisolated static func currentSystemIsDark() -> Bool {
        MainActor.assumeIsolated {
            NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    nonisolated static func applyToApp(_ isDark: Bool?) {
        MainActor.assumeIsolated {
            let wanted: NSAppearance? = isDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
            // Only when it actually differs: every set makes macOS announce
            // an appearance change.
            guard NSApplication.shared.appearance?.name != wanted?.name else { return }
            NSApplication.shared.appearance = wanted
        }
    }
    #else
    /// Linux: the app supplies the real hooks; these keep the defaults valid.
    nonisolated static func currentSystemIsDark() -> Bool { false }
    nonisolated static func applyToApp(_ isDark: Bool?) {}
    #endif
}
