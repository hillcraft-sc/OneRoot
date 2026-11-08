import AppKit

/// Tracks which OneRoot main window was most recently key. Advanced Search
/// runs in its own window and has no direct reference to any particular
/// main window's `WindowViewModel` — every open main window's
/// `MainWindowView` observes `.revealInOneRoot`, and this is how each one
/// decides whether it's the one that should act on it, so opening a search
/// result doesn't navigate every open window at once.
@MainActor
enum MainWindowFocusTracker {
    static var mostRecentWindowNumber: Int?
}
