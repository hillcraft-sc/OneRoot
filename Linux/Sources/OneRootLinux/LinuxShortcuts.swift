import Foundation

/// The keyboard shortcuts the Linux app registers, grouped for the Help
/// window's Keyboard Shortcuts topic and the Ctrl+? sheet. The accelerators
/// themselves are registered next to their actions (`AppWindow`,
/// `AppWindow+Files`, `OneRootApp`); a test checks this list against the
/// names used there so the two can't quietly drift.
enum LinuxShortcuts {
    struct Section {
        let title: String
        /// (keys, what they do)
        let shortcuts: [(String, String)]
    }

    static let sections: [Section] = [
        Section(title: "Tabs and windows", shortcuts: [
            ("Ctrl+T", "New tab"),
            ("Ctrl+Tab / Ctrl+Page Down", "Next tab"),
            ("Ctrl+Shift+Tab / Ctrl+Page Up", "Previous tab"),
            ("Ctrl+W", "Close tab (the last tab closes the window)"),
            ("Ctrl+N", "New window"),
            ("Ctrl+Alt+N", "New Workspace"),
        ]),
        Section(title: "Navigation", shortcuts: [
            ("Alt+Left / Alt+Right", "Back / Forward"),
            ("Alt+Up", "Enclosing folder"),
            ("Alt+Home", "Home folder"),
            ("Backspace", "Back (in the file list)"),
            ("Ctrl+L", "Type a path in the address bar"),
            ("Ctrl+K", "Connect to Server (smb://, sftp://, …)"),
            ("Ctrl+Shift+K", "Browse Network (servers found on your network)"),
            ("Ctrl+J", "Eject the drive or disconnect the share this tab is in"),
            ("Ctrl+R", "Reload"),
            ("Ctrl+Alt+Y", "Show all history (every folder visited)"),
        ]),
        Section(title: "Panes", shortcuts: [
            ("F9", "Show or hide the sidebar"),
            ("Shift+F9", "Show or hide the folder hierarchy"),
            ("Ctrl+I", "Show or hide the Inspector"),
            ("Ctrl+-", "Collapse all folders in the hierarchy"),
            ("Ctrl++ or Ctrl+=", "Expand the hierarchy one level"),
            ("Ctrl+\\", "Dual Pane (again to close it)"),
            ("Ctrl+Alt+\\", "Compare Panes"),
            ("Ctrl+Shift+\\", "Swap Panes"),
            ("Ctrl+`", "Switch to the other pane"),
            ("F5 / F6", "Copy / Move the selection to the other pane"),
        ]),
        Section(title: "File list", shortcuts: [
            ("Enter", "Open the selection"),
            ("Space", "Quick Look the selection (Space or Esc closes it)"),
            ("Esc", "Clear the selection"),
            ("Type letters", "Jump to the first file starting with them"),
            ("Ctrl+Enter", "Open folders in new tabs"),
            ("Ctrl+1 / Ctrl+2", "View as Grid / as List (remembered per folder)"),
            ("Ctrl+H", "Show or hide hidden files"),
            ("Ctrl+A", "Select all"),
            ("Ctrl+Shift+A", "Deselect all"),
            ("Ctrl+F or /", "Filter this folder by name"),
            ("Ctrl+Shift+F", "Advanced Search"),
        ]),
        Section(title: "Files", shortcuts: [
            ("Ctrl+C / Ctrl+X / Ctrl+V", "Copy / Cut / Paste"),
            ("Ctrl+Z", "Undo the last file operation"),
            ("Ctrl+Shift+Z or Ctrl+Y", "Redo"),
            ("F2", "Rename (several items: batch Rename)"),
            ("Delete", "Move to Trash"),
            ("Shift+Delete", "Delete permanently"),
            ("Ctrl+Shift+N", "New folder"),
            ("Ctrl+Shift+C", "Copy the path of the selection (or the folder)"),
            ("Ctrl+Shift+E", "Show the selection in the desktop's file manager"),
        ]),
        Section(title: "Tools", shortcuts: [
            ("Ctrl+Shift+D", "Find Duplicates"),
            ("Ctrl+Alt+V", "Visualize Storage"),
            ("Ctrl+Shift+O", "File Operations"),
            ("Ctrl+Alt+B", "Tools Panel: close the open tools, or open File Operations"),
        ]),
        Section(title: "General", shortcuts: [
            ("F1", "OneRoot Help"),
            ("Ctrl+?", "Keyboard shortcuts"),
            ("Ctrl+,", "Settings"),
            ("Ctrl+Q", "Quit"),
        ]),
    ]
}
