#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation // CGRect, on Linux

/// Persists the last session's windows and tabs (`SavedSession`) and the
/// Settings ▸ General toggle for reopening them. UI-agnostic: the app side
/// (`SessionRestorer`) builds and applies sessions; this stores them and
/// makes a stored one safe to reopen.
struct SessionService {
    private static let sessionKey = "com.oneroot.savedSession"
    private static let enabledKey = "com.oneroot.restoreSession"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless turned off — reopening where you left off is the default.
    /// Read with `bool(forKey:)` rather than `object(forKey:) as? Bool`: a
    /// value passed on the command line (`-com.oneroot.restoreSession NO`,
    /// handy for running a debug build without touching the real session)
    /// arrives as a string, which only `bool(forKey:)` understands.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { clear() }
    }

    func save(_ session: SavedSession) {
        guard isEnabled else { return }
        defaults.set(try? JSONEncoder().encode(session), forKey: Self.sessionKey)
    }

    func load() -> SavedSession? {
        guard isEnabled, let data = defaults.data(forKey: Self.sessionKey) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: Self.sessionKey)
    }

    /// `session` made safe to reopen today:
    /// - a tab whose folder is gone (an unplugged drive, a deleted folder)
    ///   opens at `fallbackFolder` instead;
    /// - a split pane whose folder is gone is dropped, leaving that tab single;
    /// - a window frame that isn't on any of `screens` any more (a monitor
    ///   that's been disconnected) is dropped, so it opens at the default
    ///   position rather than off-screen;
    /// - a window with no tabs is dropped, and an active-tab index is kept
    ///   in range.
    static func sanitized(
        _ session: SavedSession,
        folderExists: (String) -> Bool,
        fallbackFolder: String,
        screens: [CGRect]
    ) -> SavedSession {
        let windows = session.windows.compactMap { window -> SavedWindow? in
            guard !window.tabs.isEmpty else { return nil }
            let tabs = window.tabs.map { tab -> SavedTab in
                var tab = tab
                if !folderExists(tab.primary.path) {
                    tab.primary.path = fallbackFolder
                }
                if let secondary = tab.secondary, !folderExists(secondary.path) {
                    tab.secondary = nil
                    tab.secondaryHasFocus = false
                }
                if let root = tab.hierarchyRoot, !folderExists(root.url.path) {
                    tab.hierarchyRoot = nil
                }
                return tab
            }
            let frame = window.frame.flatMap { frame in
                screens.contains { $0.intersects(frame) } ? frame : nil
            }
            let activeTabIndex = min(max(window.activeTabIndex, 0), tabs.count - 1)
            return SavedWindow(frame: frame, tabs: tabs, activeTabIndex: activeTabIndex, layout: window.layout?.clamped)
        }
        return SavedSession(windows: windows)
    }
}
