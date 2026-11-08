import AppKit

/// Opens `url` in the user's configured editor app (see
/// `EditorPreferenceService`) — the pinned "Editor" entry in a folder's
/// Open With menu. Unlike `openInTerminal`, there's no universal default
/// to fall back to, so this is a no-op until Settings has an editor
/// configured; callers should check `EditorPreferenceService().bundleIdentifier()`
/// before even showing the menu item.
///
/// Exists as its own pinned entry — rather than just letting an editor
/// show up in the folder's auto-discovered Open With list the way `Zed`
/// does — because plenty of editors (VS Code being the canonical example)
/// open folders just fine but don't declare that support in their own
/// `Info.plist` (`LSItemContentTypes`/`CFBundleDocumentTypes`), so
/// `NSWorkspace.urlsForApplications(toOpen:)` never offers them; that's
/// also why they're missing from Finder's own folder "Open With" menu.
///
/// Same two paths as `openInTerminal`, both configured in Settings:
/// - No open-folder argument set: `NSWorkspace.open(_:withApplicationAt:)`
///   — works even for an app that doesn't declare folder support, the
///   same way dragging a folder onto its Dock icon does (both go through
///   the same Apple Event open-documents mechanism; the `Info.plist`
///   declaration only affects whether Finder/LaunchServices *offer* the
///   app automatically, not whether it can actually handle the event).
/// - An argument is set: `NSWorkspace.openApplication(at:configuration:)`
///   with `[argument, url.path]` — for an editor whose CLI needs an
///   explicit flag/subcommand first. VS Code's own `code` CLI takes the
///   folder as a bare positional (no flag needed, so this is usually left
///   blank); this stays available for ones that do need one.
func openInEditor(_ url: URL) {
    let preferences = EditorPreferenceService()
    guard let bundleIdentifier = preferences.bundleIdentifier(),
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
    if let flag = preferences.workingDirectoryFlag() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [flag, url.path]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    } else {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
