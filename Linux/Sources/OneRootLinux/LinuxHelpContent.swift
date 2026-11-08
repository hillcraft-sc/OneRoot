import Foundation
@testable import OneRoot

/// The Help window's topics for the Linux app. Same model as the Mac's
/// `HelpContent` (so `HelpSearch` works on both), but written for what the
/// Linux app actually does, with Linux key names. Update it with any
/// user-visible change, and describe only what is built.
enum LinuxHelpContent {
    static func topic(_ id: HelpTopicID) -> HelpTopic? {
        topics.first { $0.id == id }
    }

    static let topics: [HelpTopic] = [
        HelpTopic(id: .gettingStarted, title: "Getting Started", symbolName: "starred-symbolic", section: .basics, keywords: ["overview", "layout", "window"], blocks: [
            .paragraph("OneRoot is a file manager. Its window has four parts, left to right:"),
            .bullets([
                "**Destinations** \u{2014} the sidebar: Home, drives and mounts, pinned folders, the Trash, and your Workspaces.",
                "**Folder hierarchy** \u{2014} the folders inside the destination you chose, as a tree.",
                "**File list** \u{2014} what is in the current folder, as a list or a grid.",
                "**Inspector** \u{2014} a preview and details of the selection, with actions for it.",
            ]),
            .paragraph("Tabs run across the top. Under them the **Context Bar** offers what you can do right now: New with nothing selected, the selection's actions once something is, and Sort, List/Grid, Dual Pane and More on the right. Along the bottom, a status line counts items and shows free space, and **File Operations** follows copies and moves."),
            .paragraph("Choose a destination, click a folder in the hierarchy, or double-click a folder in the list to go in. Double-clicking a file opens it with its default app."),
        ], seeAlso: [.contextBar, .fileList, .navigating, .shortcuts]),

        HelpTopic(id: .navigating, title: "Navigating", symbolName: "go-next-symbolic", section: .browsing, keywords: ["path", "back", "forward", "address", "breadcrumb", "history"], blocks: [
            .paragraph("The path at the top is clickable: click a folder name to go there. Press **Ctrl+L** (or click the pencil) to type a path instead."),
            .terms([
                ("Back, Forward", "**Alt+Left**, **Alt+Right**, or the arrows beside the sidebar buttons. **Backspace** goes back in the file list. Right-click (or press and hold) an arrow to see the folders it leads to; choosing one steps back or forward to it, so the folders in between stay in the other list."),
                ("Subfolders", "The small arrow after each folder name in the path lists that folder's subfolders; right-click a folder name for Open, Open in New Tab and Copy Path, or drop files on it."),
                ("Reload", "**Ctrl+R**, or the reload button."),
                ("Recent places", "Main menu \u{25B8} **Recent Locations\u{2026}** lists the last dozen folders you visited; **Show All History\u{2026}** (**Ctrl+Alt+Y**) opens every one with a filter box."),
                ("Up one level", "**Alt+Up**"),
                ("Home", "**Alt+Home**"),
                ("New tab", "**Ctrl+T**; **Ctrl+Enter** opens the selected folders in new tabs."),
                ("Switch tabs", "**Ctrl+Tab** / **Ctrl+Page Down** and **Ctrl+Shift+Tab** / **Ctrl+Page Up**."),
                ("Tab menu", "Right-click a tab: Duplicate Tab, Move Tab to New Window, Close Other Tabs, Close Tabs to the Right."),
                ("Drag a tab", "Drag a tab along the strip to reorder it, onto another window\u{2019}s tab strip to move it there, or away from every strip to open it in a new window."),
            ]),
        ], seeAlso: [.destinations, .shortcuts]),

        HelpTopic(id: .destinations, title: "Destinations and Workspaces", symbolName: "folder-symbolic", section: .browsing, keywords: ["sidebar", "pinned", "drives", "trash", "workspace", "mount"], blocks: [
            .paragraph("The sidebar lists Home, your drives and mounts, pinned folders, the Trash and Workspaces. Right-click a row for Open in New Tab and, for pinned folders, Remove from Sidebar. To pin a folder, right-click it in the file list and choose Pin to Sidebar."),
            .paragraph("**Recents** lists the files you opened lately (the last 30 days, newest first), read from the desktop\u{2019}s `recently-used.xbel` list \u{2014} the same record GNOME Files and other GTK apps keep. A file that has since been moved or deleted is left out, and OneRoot only reads the list."),
            .paragraph("A **Workspace** is a named set of real folders, which can be on different drives. Make one with the + beside Workspaces (or **Ctrl+Alt+N**), add or remove its folders in the editor, and search all of them at once from Advanced Search."),
        ], seeAlso: [.advancedSearch]),

        HelpTopic(id: .fileList, title: "The File List: List and Grid", symbolName: "view-list-symbolic", section: .browsing, keywords: ["icons", "grid", "sort", "columns", "hidden", "group"], blocks: [
            .paragraph("Show a folder **as a list** (**Ctrl+2**) with sortable columns, or **as a grid** (**Ctrl+1**) of icons. Each folder remembers its own choice. Drag a column\u{2019}s edge to resize it; the widths are remembered. In the grid, a grouped list shows each group\u{2019}s name and item count as a heading."),
            .bullets([
                "Click a column heading to sort; click again to reverse. The Sort menu in the Context Bar does the same.",
                "Hidden files (names starting with a dot) are shown with **Ctrl+H**.",
                "**Sort \u{25B8} Group by** adds headings by name, type, date, size or tags.",
                "Right-click a column heading to show or hide columns, or to Move Left / Move Right; **More \u{25B8} Columns\u{2026}** has a switch for each. You can also drag a heading. Name always stays first.",
                "**More \u{25B8} Show All Files in Subfolders** lists every file under the folder in one list, with a **Where** column; **Show Folders** in the bar above the list goes back.",
                "Press **Space** for Quick Look: a window that previews the selected image, PDF (first page), text or file details, and plays audio and video, and follows the selection. With several items selected, **Left** / **Right** step through them; with one selected, the arrow keys move the selection in the list. **Space** or **Esc** closes it.",
                "In Grid view a slider next to the List/Grid switch sets the icon size.",
                "Type the first letters of a name to jump to it (a pause of a second starts over; repeat a letter to cycle). **Esc** clears the selection.",
                "Right-click \u{25B8} More has Copy Names without Extensions and **Show in File Manager** (**Ctrl+Shift+E**).",
                "**Ctrl+F** or **/** filters the folder by name. Filter chips appear above the list; **Search Subfolders** hands the filter to Advanced Search.",
                "Drag files onto a folder to move them (hold **Ctrl** to copy); drop on empty space to put them in this folder.",
            ]),
        ], seeAlso: [.contextBar, .fileOperations]),

        HelpTopic(id: .contextBar, title: "The Context Bar", symbolName: "view-more-symbolic", section: .browsing, keywords: ["toolbar", "actions", "paste", "new", "sort"], blocks: [
            .paragraph("The row under the tabs changes with what you have selected."),
            .bullets([
                "**Nothing selected:** **New** (folder, file, folder and open).",
                "**Items selected:** \u{201C}N selected\u{201D} with a \u{2715} (or **Shift+Ctrl+A**) that clears the selection, then Open, Cut, Copy, Rename, Compress, Extract (for archives) and Move to Trash. Folders also get Open in New Tab. In the Trash: Restore and Delete Permanently.",
                "**Paste** appears on the right while the clipboard holds files.",
                "**Sort**, the **List/Grid** switch, **Dual Pane**, and **More** (Select All, Duplicate, Copy Path, Open in Terminal, Pin, Show Hidden Files, Calculate Folder Sizes, Find Duplicates, Visualize Storage, Advanced Search) are always there.",
            ]),
            .paragraph("Every button runs the same action as its menu item and shortcut, and greys out when it does not apply."),
        ], seeAlso: [.fileOperations, .dualPane]),

        HelpTopic(id: .inspector, title: "The Inspector", symbolName: "dialog-information-symbolic", section: .browsing, keywords: ["properties", "preview", "details", "permissions", "tags"], blocks: [
            .paragraph("**Ctrl+I** shows or hides the Inspector. A Markdown file can be shown as its text or rendered (Text / Rendered, remembered). It previews the selected image, the first page of a PDF, or a text file, and lists its kind, size, location and dates, with Details, More Info and Permissions tabs. With nothing selected it describes the folder."),
        ]),

        HelpTopic(id: .dualPane, title: "Dual Pane and Compare", symbolName: "view-dual-symbolic", section: .files, keywords: ["split", "two panes", "compare", "sync"], blocks: [
            .paragraph("**Ctrl+\\** (or the Dual Pane button) splits the tab into two folders side by side. **Ctrl+`** switches panes; **F5** copies and **F6** moves the selection to the other pane."),
            .paragraph("Each pane has a header with its folder name and a Swap button (**Ctrl+Shift+\\**); drag a header onto the other pane to swap them, or off the window to open that pane in its own window. **Compare Panes** (**Ctrl+Alt+\\**, or the Context Bar button) marks what is newer, older, only here, or different in each folder, and can copy the differences either way after showing you a preview."),
        ], seeAlso: [.fileOperations]),

        HelpTopic(id: .fileOperations, title: "Working with Files", symbolName: "edit-copy-symbolic", section: .files, keywords: ["copy", "move", "rename", "trash", "undo", "delete", "compress", "zip", "batch"], blocks: [
            .bullets([
                "**Copy, Cut, Paste:** Ctrl+C, Ctrl+X, Ctrl+V. Name clashes ask whether to replace, keep both, skip, or merge folders.",
                "**Rename:** F2. With several items selected it opens the batch Rename dialog (replace text, add text, numbering, change case) with a live preview; it applies all or nothing and can be undone.",
                "**Trash:** Delete moves to the Trash; Shift+Delete deletes permanently after asking. Restore is in the Trash.",
                "**Undo / Redo:** Ctrl+Z and Ctrl+Shift+Z undo copies, moves, renames, new folders and trashing.",
                "**Compress / Extract:** in the Context Bar and right-click menu; Settings chooses Zip or 7z and where the archive goes.",
            ]),
            .paragraph("The **File Operations** panel (**Ctrl+Shift+O**) shows each copy or move with real progress, speed and time left, with Pause, Cancel, Start Now and Retry. Settings can verify copies after they finish."),
        ], seeAlso: [.dualPane, .settings]),

        HelpTopic(id: .quickActions, title: "Quick Actions", symbolName: "applications-engineering-symbolic", section: .files, keywords: ["resize", "convert", "image", "pdf", "combine", "metadata", "exif", "markdown", "html", "jpeg", "png"], blocks: [
            .paragraph("Select images, PDFs or text files and use **Quick Actions** in the Context Bar (or the right-click menu). Each action opens a sheet that lists exactly what will be written; it always makes **new files beside the originals** and never replaces anything. Undo removes what it made."),
            .bullets([
                "**Resize Images:** by longest side or percentage. Never enlarges. Quality applies to JPEG.",
                "**Convert Images:** to JPEG, PNG or TIFF (transparency becomes white in JPEG). Animated images and multi-page TIFFs keep their first frame.",
                "**Remove Metadata:** copies of JPEG and PNG files without location, camera, IPTC and XMP details, byte for byte otherwise; the orientation is kept. Other formats are re-encoded.",
                "**Combine into PDF:** PDFs, images and text files in the order you set, as one PDF. Password-protected PDFs are refused.",
                "**Convert to PDF:** plain text files on A4 or Letter pages in a monospaced font.",
                "**Text to Markdown, Markdown to HTML, HTML to Markdown:** with a preview of the first file.",
            ]),
            .paragraph("Resized and converted copies carry no metadata (GdkPixbuf writes none). Word, RTF and OpenDocument files are not converted on Linux."),
        ], seeAlso: [.fileOperations]),

        HelpTopic(id: .advancedSearch, title: "Searching", symbolName: "edit-find-symbolic", section: .files, keywords: ["find", "filter", "duplicates", "regex", "saved", "export"], blocks: [
            .paragraph("**Ctrl+F** filters the current folder by name. **Ctrl+Shift+F** opens **Advanced Search**: subfolders, file contents, size, dates and kind, saved queries, search across a Workspace, Show as Terminal Command, and Export (CSV, plain text, Markdown, HTML)."),
            .paragraph("**Find Duplicates** (**Ctrl+Shift+D**) lists identical files in the folder (both folders in Dual Pane); you tick the copies to trash and one of each set always stays. **Visualize Storage** (**Ctrl+Alt+V**) shows what is taking up space, by folder, type, age and tag."),
        ], seeAlso: [.destinations]),

        HelpTopic(id: .networkShares, title: "Network Locations", symbolName: "folder-remote-symbolic", section: .connecting, keywords: ["smb", "samba", "windows share", "nfs", "sftp", "ftp", "webdav", "server", "mount", "gvfs", "connect"], blocks: [
            .paragraph("**Ctrl+K** (or main menu \u{25B8} **Connect to Server\u{2026}**) opens a network address through GVfs, the same layer GNOME Files uses: `smb://server/share`, `nfs://`, `sftp://host/path`, `ftp://`, `dav://`. Type a user name and password if it needs one; **Remember the login** keeps it in the desktop keyring (never in OneRoot\u{2019}s settings). **Add to Favorites** saves the address for next time."),
            .paragraph("**Network** in the sidebar (or **Ctrl+Shift+K**) lists your **Favorites** at the top, each with a delete button, then the servers the network announces (through Avahi/Bonjour; that needs `gvfs-dnssd` and the Avahi service). Choosing one connects at once with the login remembered for that server. **Enter Address\u{2026}** opens Connect to Server (**Ctrl+K**), where **Add to Favorites** keeps a server in the Network window. **Disconnect** is in a mounted share\u{2019}s right-click menu."),
            .paragraph("You can also type an address in the address bar (**Ctrl+L**). A location that needs a login says so; use Connect to Server for those. Once mounted, the share is an ordinary folder in the file list and appears under Locations."),
            .paragraph("It needs GVfs with its FUSE bridge (`gvfs`, `gvfs-backends`, `gvfs-fuse`) and, to remember logins, a Secret Service such as GNOME Keyring or KeePassXC. Without gvfs-fuse the share connects but can\u{2019}t be shown as a folder, and OneRoot says so."),
        ], seeAlso: [.copyViaSSH, .destinations]),

        HelpTopic(id: .copyViaSSH, title: "Copy via SSH", symbolName: "network-server-symbolic", section: .connecting, keywords: ["scp", "ssh", "server", "remote", "key", "password", "keyring"], blocks: [
            .paragraph("Select files or folders and choose **Copy via SSH\u{2026}** (right-click \u{25B8} More, or the main menu). Enter the host, port, user name and the remote folder (`~/` is the login folder), then **Copy**. OneRoot runs `scp` with your SSH keys and agent, so a server that already works in a terminal works here. A password is only needed when the server asks for one; a key\u{2019}s passphrase goes in the same field."),
            .paragraph("**Save These Details** keeps a destination; with **Remember the password in the keyring** its password goes to the desktop keyring. **Settings \u{25B8} SSH** edits or removes saved destinations and can **Install Key on Server**, which logs in once with the password and adds your public key so later copies need none."),
            .paragraph("The first time you copy to a server, OneRoot shows its host-key fingerprint; **Trust and Copy** saves exactly that key to `~/.ssh/known_hosts`, so compare it with one from the server\u{2019}s owner first. If a known server\u{2019}s key has changed, the copy stops with ssh\u{2019}s warning and OneRoot never overrides it. A window shows scp\u{2019}s own progress for the file being sent, with Cancel. Copying shows a message when it starts and when it ends \u{2014} there is no progress bar, because scp reports none here."),
        ], seeAlso: [.networkShares, .settings]),

        HelpTopic(id: .settings, title: "Settings and Themes", symbolName: "preferences-system-symbolic", section: .customizing, keywords: ["preferences", "appearance", "theme", "dark", "terminal", "archive"], blocks: [
            .paragraph("**Ctrl+,** opens Settings: General (verify copies, folder sizes, friendly dates, warn before closing the last tab, reopen windows and tabs from the last session), Address bar (clickable path or a plain text field), Appearance (OneRoot, System, Catppuccin, Gruvbox, Nord, Tokyo Night, in light or dark), Archives, Terminal (which terminal Open in Terminal uses), Editor (the app for Open in Editor on a folder) and SSH (saved Copy via SSH destinations)."),
        ], seeAlso: [.fileOperations]),

        HelpTopic(id: .shortcuts, title: "Keyboard Shortcuts", symbolName: "input-keyboard-symbolic", section: .basics, keywords: ["keys", "hotkeys", "accelerator", "ctrl"], blocks:
            LinuxShortcuts.sections.flatMap { [HelpBlock.heading($0.title), HelpBlock.shortcuts($0.shortcuts)] }
        ),
    ]
}
