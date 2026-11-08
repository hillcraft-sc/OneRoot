import AppKit
import SwiftUI

@main
struct OneRootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // ⌘N (SwiftUI's default "New Window") opens independent windows,
        // each with its own OneRoot-native TabBarView (⌘T) — but never as
        // native macOS window tabs. Without this, macOS auto-groups
        // multiple windows of the same app into its own tab strip on top
        // of ours, which is exactly the confusing double-tab-bar this once
        // caused before ⌘N was (temporarily) removed entirely.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // No title bar: the sidebar runs to the top under the window's
        // buttons, and the tab strip sits where the title would be.
        WindowGroup {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppConfig.displayName)") { Self.showAboutPanel() }
                CheckForUpdatesMenuItem()
            }
            FileMenuCommands()
            EditMenuCommands()
            ViewMenuCommands()
            GoMenuCommands()
            HelpMenuCommands()
        }

        Settings {
            SettingsView().themedWindow()
        }

        Window("\(AppConfig.displayName) Help", id: Self.helpWindowID) {
            HelpView().themedWindow()
        }

        Window("Advanced Search", id: Self.advancedSearchWindowID) {
            AdvancedSearchView().themedWindow()
        }

        Window("Find Duplicates", id: Self.duplicatesWindowID) {
            DuplicatesView().themedWindow()
        }

        Window("Software Update", id: Self.updateWindowID) {
            UpdateView().themedWindow()
        }
        .windowResizability(.contentSize)

        // The full navigation history — the Go menu's "Recent Locations"
        // submenu only shows the most recent handful; "Show All History…"
        // opens this.
        Window("History", id: Self.historyWindowID) {
            HistoryView().themedWindow()
        }

        // The destination for a torn-off tab (see `DraggableTabView`'s
        // `onTearOff` in `TabBarView`): dragging a tab past any OneRoot
        // tab bar opens one of these with `TabHandoffCenter`'s token as
        // the value, and `RootView`/`MainWindowView` pick the actual
        // `Tab` and drop screen point back up by that token instead of
        // starting a normal fresh-home-directory window.
        WindowGroup(id: Self.tabHandoffWindowID, for: UUID.self) { $token in
            RootView(handoffToken: token)
        }
        .windowStyle(.hiddenTitleBar)

        // One small floating window per in-flight Copy/Move/Compress/
        // Extract — keyed by the operation's own id so several can be open
        // at once, matching Finder's own stacked-copy-windows behavior
        // rather than one window with several rows. Opened by `RootView`
        // whenever `FileOperationProgressCenter.shared.operations` gains a
        // new entry; closes itself once that entry is gone.
        WindowGroup(id: Self.fileOperationProgressWindowID, for: UUID.self) { $operationID in
            if let operationID {
                FileOperationProgressView(operationID: operationID).themedWindow()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    static let helpWindowID = "help"
    static let advancedSearchWindowID = "advancedSearch"
    static let duplicatesWindowID = "duplicates"
    static let updateWindowID = "softwareUpdate"
    static let historyWindowID = "history"
    static let fileOperationProgressWindowID = "fileOperationProgress"
    static let tabHandoffWindowID = "tabHandoff"

    /// Overrides the default "About OneRoot" item to add real credits text
    /// to the standard panel — name/version/copyright/icon still come from
    /// the bundle automatically, same as the panel Xcode gives you for
    /// free; this just fills in the one part it can't know on its own.
    private static func showAboutPanel() {
        let credits = NSMutableAttributedString(string: """
        A fast, native file manager for macOS: tabs, a folder tree, breadcrumbs, an Inspector, \
        Dual Pane, Workspaces, powerful search, and file operations you can undo.

        Built with SwiftUI and AppKit, system frameworks only \u{2014} no third-party dependencies. \
        Signed with Developer ID and notarized by Apple.

        Free software under the GNU GPL v3. Source: github.com/hillcraft-sc/OneRoot
        """)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        credits.addAttributes(
            [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

/// OneRoot ▸ Check for Updates… (#36).
private struct CheckForUpdatesMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check for Updates\u{2026}") {
            UpdateCenter.shared.checkNow()
            openWindow(id: OneRootApp.updateWindowID)
        }
    }
}
