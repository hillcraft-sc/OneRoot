import Foundation

/// The single source of truth for "what shortcut does what" — backs both the
/// full Help window's "Keyboard Shortcuts" topic (`HelpContent`) and the ⌘B quick popover, so
/// the two can never drift out of sync.
enum KeyboardShortcutReference {
    struct Section {
        let title: String
        /// (key combination, what it does)
        let shortcuts: [(String, String)]
    }

    static let sections: [Section] = [
        Section(title: "Tabs & Windows", shortcuts: [
            ("\u{2318}T", "New tab"),
            ("⌥\u{2318}T", "Duplicate the active tab"),
            ("⌃\u{2318}T", "Move the active tab to a new window"),
            ("\u{2318}W", "Close tab (closes the window on the last tab)"),
            ("⌃\u{2318}W", "Close other tabs"),
            ("⌃⌥\u{2318}W", "Close tabs to the right"),
            ("⌃⇥", "Next tab"),
            ("⌃⇧⇥", "Previous tab"),
            ("\u{2318}N", "New window"),
        ]),
        Section(title: "Navigation", shortcuts: [
            ("\u{2318}[", "Back"),
            ("\u{2318}]", "Forward"),
            ("\u{2318}↑", "Up one level"),
            ("\u{2318}R", "Refresh"),
            ("⇧\u{2318}G", "Go to Folder (type a path in the address bar)"),
            ("⌥\u{2318}C", "Copy the path of the selection (or of the current folder)"),
            ("⌥\u{2318}Y", "Show All History"),
            ("\u{2318}L", "Reveal in Finder"),
        ]),
        Section(title: "Panes & Volumes", shortcuts: [
            ("⌃\u{2318}S", "Show/hide the destinations sidebar"),
            ("⌃\u{2318}H", "Show/hide the folder hierarchy"),
            ("⌥\u{2318}I or ⇧\u{2318}P", "Show/hide the Inspector"),
            ("⌃\u{2318}B", "Show/hide the tool row (File Operations, Visualize)"),
            ("\u{2318}K", "Connect to Server…"),
            ("\u{2318}J", "Eject/Disconnect the drive or share the tab is in"),
            ("\u{2318}− / \u{2318}+", "Collapse all / expand top level (folder hierarchy)"),
        ]),
        Section(title: "File List", shortcuts: [
            ("\u{2318}O", "Open the selection"),
            ("⌥\u{2318}O", "Browse into a package (e.g. a .app) instead of launching it"),
            ("Space or \u{2318}Y", "Quick Look"),
            ("Esc or ⌥\u{2318}A", "Deselect all"),
            ("⇧\u{2318}.", "Show/hide hidden files"),
            ("\u{2318}1 / \u{2318}2", "View as Icons / as List (remembered per folder)"),
            ("\u{2318}\\", "Dual Pane: two folders side by side (again to close it)"),
            ("⌥\u{2318}\\", "Swap the two panes' sides"),
            ("F5 or ⇧\u{2318}C", "Copy the selection to the other pane"),
            ("F6 or ⇧\u{2318}M", "Move the selection to the other pane"),
            ("/", "Focus the search field"),
            ("⌥\u{2318}/", "Advanced Search"),
        ]),
        Section(title: "File Operations", shortcuts: [
            ("Return", "Rename the selection (several items: the batch Rename dialog)"),
            ("\u{2318}⌫ or ⌫", "Move to Trash"),
            ("\u{2318}C / \u{2318}X / \u{2318}V", "Copy / Cut / Paste"),
            ("\u{2318}Z / ⇧\u{2318}Z", "Undo / Redo the last file operation"),
            ("⇧\u{2318}N", "New Folder"),
            ("⌥\u{2318}N", "New Folder and Open"),
            ("\u{2318}F", "New File"),
        ]),
        Section(title: "General", shortcuts: [
            ("\u{2318}B", "This shortcut list"),
            ("\u{2318},", "Settings"),
            ("\u{2318}?", "OneRoot Help"),
        ]),
    ]
}
