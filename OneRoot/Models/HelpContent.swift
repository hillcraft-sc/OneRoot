import Foundation

/// Everything in the Help window, organized by task rather than by build
/// phase. Mirrors what's actually shipped (see `README.md`) — update it
/// alongside any user-visible change.
enum HelpContent {
    static func topic(_ id: HelpTopicID) -> HelpTopic? {
        topics.first { $0.id == id }
    }

    static let topics: [HelpTopic] = [
        HelpTopic(id: .gettingStarted, title: "Getting Started", symbolName: "sparkles", section: .basics, keywords: ["overview", "layout", "window", "full disk access"], blocks: [
            .paragraph("OneRoot is a file manager for the Mac. Its window has four parts, left to right:"),
            .bullets([
                "**Destinations** \u{2014} the sidebar of places to start from: your home folder, pinned folders, cloud storage, drives and shares, the Trash, and your Workspaces.",
                "**Folder hierarchy** \u{2014} the folders inside the destination you chose, as a tree you can expand.",
                "**File list** \u{2014} what's in the current folder, as a list or as icons.",
                "**Inspector** \u{2014} a preview and the details of whatever's selected, with actions for it.",
            ]),
            .paragraph("Tabs run across the top, level with the window's buttons, with the search field and the buttons that show or hide each part at their right. Above the file list are Back, Forward, Up and the **path**, and under the path the **Context Bar**, which offers what you can do right now: New, Sort, and View with nothing selected, and the selection's actions (Copy, Cut, Rename, Trash, \u{2026}) once something is. A status line along the bottom counts the items and shows the free space."),
            .paragraph("Two tools sit in a row along the bottom, hidden until you want them (**\u{2303}\u{2318}B**, View \u{25B8} Tools Panel): **File Operations**, which follows copies and moves, and **Visualize**, which shows what's taking up space."),
            .paragraph("OneRoot isn't sandboxed, so it needs **Full Disk Access** to read most folders. If you haven't granted it yet, launch OneRoot and follow the onboarding screen's link straight to Privacy & Security \u{2192} Full Disk Access."),
            .paragraph("Choose a destination to go there, click a folder in the hierarchy to browse it, or double-click a folder in the file list to go into it. Double-clicking a file opens it with its default app."),
            .paragraph("Used Windows before? **Coming from Windows** lists Explorer's names and keys next to OneRoot's."),
        ], seeAlso: [.comingFromWindows, .destinations, .contextBar, .inspector, .shortcuts]),

        HelpTopic(id: .comingFromWindows, title: "Coming from Windows", symbolName: "arrow.left.arrow.right.square", section: .basics, keywords: ["Explorer", "File Explorer", "PC", "switcher", "Ctrl", "Alt"], blocks: [
            .paragraph("OneRoot works much like File Explorer: a sidebar, a folder tree, tabs, a path you can click or type, columns you can sort, Cut and Paste, and right-click menus with everything in them. Most of what's different is macOS itself. Here's where to find what you know."),
            .heading("Names"),
            .terms([
                ("File Explorer", "OneRoot. (macOS's own file manager is **Finder**; OneRoot can stand in for it.)"),
                ("This PC, drive letters (C:, D:)", "**Locations** in the sidebar. macOS has no drive letters: the startup disk is usually **Macintosh HD**, and every other drive, USB stick, or share appears under it in `/Volumes`."),
                ("C:\\Users\\you", "Your home folder, `/Users/you`, written `~` for short. Paths use `/`, not `\\`."),
                ("Quick access", "**Pinned** in the sidebar (right-click a folder \u{25B8} Pin to Sidebar), and **Go \u{25B8} Recent Locations**."),
                ("Libraries", "**Workspaces**: a named set of real folders, which can be on different drives."),
                ("Properties", "The **Inspector** (**\u{2325}\u{2318}I**). macOS calls this Get Info."),
                ("Preview pane, Details pane", "The **Inspector** too, or **Space** for a Quick Look of the selection."),
                ("Recycle Bin", "**Trash**, under Special in the sidebar. Restore is there as on Windows."),
                ("Map network drive", "**Connect to Server** (**\u{2318}K**), with an address like `smb://server/share`."),
                ("Compressed (zipped) folder", "**Compress** and **Extract** in the Context Bar and the right-click menu."),
                ("Copy as path", "**Copy Path** (**\u{2325}\u{2318}C**). **Copy Name** and **Copy Name without Extension** are in the right-click and Edit menus."),
                ("Right-drag (Copy here / Move here)", "Hold **\u{2303} Control** while you drop for **Move Here**, **Copy Here**, or **Make Alias Here**."),
                ("Open in Terminal / Command Prompt", "**Open in Terminal** in the right-click menu."),
                ("The copy progress dialog", "The **File Operations** card (**\u{2303}\u{2318}B**), with Cancel, Retry, and a list of what finished."),
                ("Show hidden items", "**\u{21E7}\u{2318}.** (View \u{25B8} Show Hidden Files)."),
            ]),
            .heading("Keys"),
            .paragraph("On a Mac, **\u{2318} Command** does most of what **Ctrl** does on Windows, and **\u{2325} Option** is the Alt key. To right-click, click with two fingers on a trackpad or hold **Control** while you click."),
            .terms([
                ("Ctrl+C, Ctrl+X, Ctrl+V", "**\u{2318}C**, **\u{2318}X**, **\u{2318}V**. Cut and paste moves files, as in Explorer (Finder can't cut files; OneRoot can)."),
                ("Ctrl+Z, Ctrl+Y", "**\u{2318}Z** and **\u{21E7}\u{2318}Z**: Undo and Redo of copies, moves, renames, new folders, and trashing."),
                ("F2", "**Return** renames the selection."),
                ("Enter (open)", "**\u{2318}O**, or double-click. Return renames on a Mac."),
                ("Delete", "**\u{2318}\u{232B}** or **\u{232B}** moves to the Trash, after asking."),
                ("Shift+Delete", "Move to the Trash, then **Delete Immediately** from inside the Trash."),
                ("Alt+\u{2190}, Alt+\u{2192}", "**\u{2318}[** and **\u{2318}]**: Back and Forward."),
                ("Alt+\u{2191}, Backspace", "**\u{2318}\u{2191}**: up one level."),
                ("F5 (refresh)", "**\u{2318}R** (View \u{25B8} Refresh). In OneRoot, F5 copies to the other pane in Dual Pane."),
                ("Ctrl+L, Alt+D", "**\u{21E7}\u{2318}G**, or click the empty space in the path, to type a path."),
                ("Ctrl+F, F3", "**/** filters this folder by name; **\u{2325}\u{2318}/** opens Advanced Search for subfolders and file contents."),
                ("Ctrl+T, Ctrl+W, Ctrl+N", "**\u{2318}T**, **\u{2318}W**, **\u{2318}N**: new tab, close tab, new window."),
                ("Ctrl+Shift+N", "**\u{21E7}\u{2318}N**: New Folder."),
                ("Alt+Enter", "**\u{2325}\u{2318}I**: show the Inspector."),
            ]),
            .heading("Things that work differently"),
            .bullets([
                "**Return renames, it doesn't open.** Use \u{2318}O or double-click to open.",
                "**Apps are bundles.** An app such as Safari.app is really a folder that opens as one thing. \u{2325}\u{2318}O browses inside it.",
                "**Eject before unplugging.** Use the \u{23CF} button beside a drive in the sidebar, or **\u{2318}J**, before you pull out a USB drive.",
                "**File extensions** can be hidden per file by macOS. The **Type** column says what a file is, and the **Extension** column (right-click a column header to show it) shows the extension itself.",
                "**Some folders are protected.** macOS asks before an app can read Desktop, Documents, or Downloads; giving OneRoot Full Disk Access once covers them all.",
            ]),
        ], seeAlso: [.gettingStarted, .inspector, .fileOperations, .shortcuts]),

        HelpTopic(id: .destinations, title: "Destinations & Folder Hierarchy", symbolName: "sidebar.left", section: .browsing, keywords: ["sidebar", "tree", "pin", "favorites", "Quick access", "drives", "eject", "This PC", "Recents", "recent files", "Shared", "shared with me"], blocks: [
            .paragraph("The **destinations** sidebar on the far left lists the places to start from, in this order:"),
            .bullets([
                "**Home** \u{2014} your home folder.",
                "**Recents** \u{2014} files you've opened in the last 30 days, newest first, from anywhere in your home folder (not ~/Library or hidden files). It's a list, not a folder: a **Where** column shows each file's folder.",
                "**Shared** \u{2014} items in iCloud Drive shared with you or by you. Only iCloud Drive: other cloud services don't tell macOS what's shared.",
                "**Pinned** \u{2014} folders you've pinned, only shown once something's pinned.",
                "**Cloud** \u{2014} iCloud Drive, Dropbox, Google Drive, Nextcloud, and other cloud-storage folders, when there are any.",
                "**Locations** \u{2014} the boot disk, Applications, then USB drives, network shares, and mounted disk images.",
                "**Special** \u{2014} the Trash.",
                "**Workspaces** \u{2014} your named sets of project folders (see **Workspaces**).",
            ]),
            .paragraph("At the bottom, a small card shows how full the startup disk is; its gear holds Connect to Server and Settings."),
            .paragraph("Recents opens newest first, by Date Last Opened. While Recents or Shared is showing, the folder hierarchy closes (they aren't inside any folder) and comes back when you go to a folder \u{2014} unless you'd closed it yourself. In **Recents** and **Shared** you can open, Quick Look, copy, drag, rename, tag, and trash items as anywhere else; what needs a real folder (Paste, New Folder, Up) is off there, and the folder hierarchy stays as it was. Back and Forward step in and out of them like any folder, and a tab showing one reopens in it."),
            .paragraph("Choosing a destination takes the current tab there and roots the **folder hierarchy** beside it at that place, so the tree shows just that location rather than the whole disk. Browse anywhere inside it and the hierarchy stays put; go somewhere outside it (Up from your home folder, say) and it switches to the nearest destination that contains where you are. Each tab remembers its own hierarchy and what was expanded in it."),
            .paragraph("Right-click a destination for Open in New Tab, Copy Path, Reveal in Finder, and Open in Terminal, plus Remove from Sidebar (pinned folders), Eject/Disconnect (drives and shares, also the \u{23CF} button on the row), or Empty Trash. Drop files on a destination to move them there (hold \u{2325} to copy); dropping on the Trash moves them to the Trash."),
            .paragraph("Right-click anything in the hierarchy for a context menu: Open in New Tab, Show in File List, Reveal in Finder, Eject/Disconnect (for a volume or share at the top), Cut/Copy/Paste, Rename, Move to Trash, Pin/Unpin, Get Info, Copy Path, Open in Terminal, and New Folder. **\u{2318}\u{2212}** collapses every folder; **\u{2318}+** expands the top level."),
            .paragraph("To pin a folder, right-click it in the hierarchy and choose **Pin to Sidebar**, or select it and choose **Pin** in the Inspector."),
            .heading("Showing and hiding parts of the window"),
            .paragraph("Show or hide each part from the View menu or the buttons at the right of the tab strip: **Destinations** (\u{2303}\u{2318}S), **Folder Hierarchy** (\u{2303}\u{2318}H), **Inspector** (\u{2325}\u{2318}I), and the **Tools Panel** (\u{2303}\u{2318}B). Drag a divider to resize a part; each window remembers its own layout, and new windows start with the one you last chose. When a window is too narrow for everything, the Inspector steps aside first, then the hierarchy, then the destinations, and they come back as the window grows. **View \u{25B8} Reset Window Layout** puts every part back to its default size and visibility."),
        ], seeAlso: [.workspaces, .navigating, .networkShares]),

        HelpTopic(id: .workspaces, title: "Workspaces", symbolName: "square.stack.3d.up", section: .browsing, keywords: ["project", "Libraries", "collection", "group of folders"], blocks: [
            .paragraph("A **Workspace** is a named set of real folders for one project \u{2014} say `~/repos/phoenix`, `~/Documents/Phoenix`, and a design folder on a network share. It isn't a folder itself: nothing is moved, copied, or merged, and each folder stays exactly where it is."),
            .heading("Making one"),
            .bullets([
                "Click **+** beside **Workspaces** in the sidebar, give it a name and an icon, and add folders with **Add Folder\u{2026}**.",
                "Drop folders on a Workspace in the sidebar to add them. They're added as references; nothing moves.",
                "Select a folder and choose **Add to Workspace** from the Inspector's **More** menu, or use the Context Bar's **More \u{25BE}** for the folder you're in. Both also offer a new Workspace containing that folder.",
            ]),
            .heading("Using one"),
            .paragraph("Choose a Workspace in the sidebar and the tab goes to its first folder that's available, while the folder hierarchy shows **every folder as its own root**, each with its real name. Two folders with the same name get the folder they're in added, such as \u{201C}Design (Archive)\u{201D}; hover over a root to see its full path, and right-click it for **Copy Path** and **Reveal in Finder**."),
            .paragraph("The tab stays in the Workspace while you browse inside its folders. Going anywhere else, or choosing a destination, ends it, and the hierarchy shows ordinary folders again. A Workspace tab is named after the Workspace and has the Workspace's icon; its tooltip says which folder you're in. Each tab remembers its Workspace, and so does a reopened session."),
            .heading("Changing one"),
            .paragraph("Right-click a Workspace for **Edit Workspace\u{2026}** (rename it, change its icon, add or remove folders, drag folders to reorder them), **Open in New Tab**, and **Delete Workspace\u{2026}**. Removing a folder or deleting a Workspace never touches the folders themselves."),
            .paragraph("Workspaces are stored on this Mac only; they aren't synced."),
            .heading("Searching a Workspace"),
            .paragraph("In a Workspace tab, type in the search field (or add a filter): the filter row then has **Search Workspace**, which searches every folder of the Workspace at once in Advanced Search, with the same filters. In Advanced Search itself, **Workspace \u{25BE}** beside Choose\u{2026} picks a Workspace as the place to search. A folder that isn't there right now (an unplugged drive) is skipped."),
        ], seeAlso: [.destinations, .tabs]),

        HelpTopic(id: .tabs, title: "Tabs & Windows", symbolName: "macwindow.on.rectangle", section: .browsing, keywords: ["session", "restore", "tear off", "close other tabs", "close all tabs", "next tab", "switch tabs"], blocks: [
            .paragraph("Each tab has its own location, back/forward history, sort order, folder hierarchy, and Inspector section \u{2014} the destinations sidebar is shared across a window's tabs."),
            .bullets([
                "**\u{2318}T** opens a new tab (at your home folder).",
                "**\u{2325}\u{2318}T** duplicates the active tab (same location, fresh history) right next to it.",
                "**\u{2303}\u{2318}T** moves the active tab into a new window of its own (File \u{25B8} Move Tab to New Window), the keyboard version of dragging it off the tab bar. It needs at least two tabs, and a split tab keeps both panes.",
                "**\u{2318}W** closes the current tab; closing the last tab closes the window, and asks for confirmation first (turn this off in **Settings \u{25B8} General**).",
                "**\u{2303}\u{21E5}** and **\u{2303}\u{21E7}\u{21E5}** go to the next and previous tab (View \u{25B8} Show Next Tab / Show Previous Tab), wrapping round at the ends.",
                "**\u{2303}\u{2318}W** closes every tab but the current one (View \u{25B8} Close Other Tabs); **\u{2303}\u{2325}\u{2318}W** closes the tabs to its right (View \u{25B8} Close Tabs to the Right). Neither ever closes the window.",
                "**\u{2318}N** opens a new window.",
                "\u{2318}-click a folder in the file list, or \u{201C}Open in New Tab\u{201D} from its context menu or the sidebar's, opens it in a new tab instead of navigating the current one. **\u{21E7}\u{2318}T** does the same for whichever folder is selected in the file list.",
            ]),
            .paragraph("**Right-click a tab** for Close Tab, Close Other Tabs, Close Tabs to the Right, Duplicate Tab, Move Tab to New Window, and New Tab \u{2014} for that tab, whichever one is active."),
            .paragraph("When there are more tabs than fit, the rest are in the **\u{00BB}** menu at the end of the tab strip; the tab you're on always stays visible."),
            .paragraph("Drag a tab left or right to reorder it. Drag one out past the tab bar \u{2014} onto empty desktop, or onto another window \u{2014} and it tears off into its own new window, the same way Safari's tabs do; drag it onto another OneRoot window's tab bar instead and it merges in there, wherever you drop it. Dragging out the last tab in a window closes that window, as \u{2318}W would. Dragging files over a tab switches to it, so you can drop them into its folder."),
            .paragraph("When OneRoot opens, it brings back the windows and tabs you had open when it last quit: each tab's folder, sort order, Workspace, and split panes, with the same tab active and each window where it was. A folder that's gone since (an unplugged drive, a deleted folder) opens at your home folder instead, and a window from a monitor that's no longer connected opens at the default position. Turn this off in **Settings \u{25B8} General**."),
        ], seeAlso: [.dualPane, .navigating]),

        HelpTopic(id: .dualPane, title: "Dual Pane", symbolName: "rectangle.split.2x1", section: .browsing, keywords: ["split", "two panes", "commander", "side by side", "F5", "F6", "compare", "sync", "synchronize", "differences", "backup"], blocks: [
            .paragraph("**Dual Pane** (**\u{2318}\\\\**, View \u{25B8} Dual Pane, or the **Dual Pane** button in the Context Bar) shows a second folder beside the first in the current tab, which is handy for sorting files between two places. Both panes start at the folder you were in; each then has its own location, selection, sort order, and back/forward history."),
            .paragraph("The pane you last clicked in has a highlighted header, and the hierarchy, path, Context Bar, Inspector, Visualize, and status line all follow it."),
            .shortcuts([
                ("F5 or \u{21E7}\u{2318}C", "Copy the selection to the other pane"),
                ("F6 or \u{21E7}\u{2318}M", "Move the selection to the other pane"),
                ("\u{2325}\u{2318}\\", "Swap the two panes' sides"),
                ("\u{2318}\\", "Close the other pane"),
            ]),
            .heading("Comparing the two folders"),
            .paragraph("With Dual Pane on, click **Compare** (the \u{21C4} button in the Context Bar) or choose **View \u{25B8} Compare Panes**. OneRoot compares both folders, subfolders included, by name, size, and date modified (it doesn't read file contents), and labels each item in the list: **Newer**, **Only here**, **Older** (newer in the other pane), or **Differs** (changed on both sides, or the same date with a different size). A folder is Newer when only its side has newer or extra things inside."),
            .paragraph("The bar above the panes sums up each side. **Differences Only** hides what matches. **Copy to Right \u{2192}** and **\u{2190} Copy to Left** copy what's newer or missing into the other folder, after showing exactly which items will go: folders are merged, a file is only replaced by a newer one (the old one goes to the Trash), nothing is deleted, and files that differ without being newer are listed and left alone. Undo reverses the copy. The comparison runs again afterwards, and ends when either pane goes to another folder; **Done** ends it too."),
            .paragraph("On most Mac keyboards F5 and F6 need **fn**, which is why \u{21E7}\u{2318}C and \u{21E7}\u{2318}M do the same. Both are also in the right-click menu and the File menu, and they get the usual Replace/Keep Both prompt, progress, and Undo. You can also drag files from one pane to the other."),
            .paragraph("Each pane's header strip can be dragged. Drop it on the other pane's header to swap their sides. Drag it out of the window and let go, and that pane opens in a new window of its own as an ordinary tab, while the tab it came from goes back to one pane. Letting go anywhere else inside the window cancels the drag."),
            .paragraph("Pressing \u{2318}\\ again closes the second pane; the pane you're working in is the one that stays. Other tabs aren't affected, and a split tab keeps both panes if you drag it into another window."),
        ], seeAlso: [.tabs, .fileOperations]),

        HelpTopic(id: .navigating, title: "Navigating", symbolName: "location", section: .browsing, keywords: ["address bar", "breadcrumbs", "path", "go to folder", "history", "recent"], blocks: [
            .paragraph("The path shows where you are as clickable segments, like Explorer's: **Macintosh HD \u{203A} Users \u{203A} you \u{203A} Documents**. Click any segment to jump there, or click a **\u{203A}** for a menu of that folder's subfolders. Right-click a segment to open it in a new tab or copy its path. Drop files onto a segment to move them into that folder (hold **\u{2325}** to copy instead), the same as dropping onto a folder in the list or sidebar. When the path is too long to fit, the leading segments fold into a **\u{2026}** menu."),
            .paragraph("To type a path instead, click the pencil at the right end of the path (or the empty space beside it), or press **\u{21E7}\u{2318}G** (Go \u{25B8} Go to Folder\u{2026}). Type a path and press Return; Esc, or clicking away, switches back to segments, and a path that doesn't exist is flagged without leaving the folder you're in. `~` expands to your home folder, and an `smb://`, `afp://`, or `nfs://` address mounts that share on the fly. As you type, a dropdown suggests matching subfolder names \u{2014} \u{2191}/\u{2193} to move through it, Return or a click to accept, Esc to dismiss. (Prefer a plain, always-editable path? Set **Settings \u{25B8} General \u{25B8} Address bar** to **Text field**.)"),
            .paragraph("The copy button next to the pencil copies the folder's full path; **\u{2325}\u{2318}C** (Edit \u{25B8} Copy Path) copies the selected items' paths, or the folder's when nothing is selected."),
            .shortcuts([
                ("\u{2318}[", "Back"),
                ("\u{2318}]", "Forward"),
                ("\u{2318}\u{2191}", "Up one level"),
                ("\u{2318}R", "Refresh: re-read both panes and the folder tree"),
                ("\u{21E7}\u{2318}G", "Go to Folder: type a path"),
                ("\u{2325}\u{2318}C", "Copy Path: the selection's paths, or the current folder's"),
                ("\u{2318}L", "Reveal the selection in Finder"),
            ]),
            .paragraph("OneRoot updates on its own when files change, but some places don\u{2019}t report changes \u{2014} network shares (NFS and SMB) especially, when another computer changes them. The **\u{21BB}** button after Up, or **\u{2318}R** (View \u{25B8} Refresh), re-reads the tab\u{2019}s folder (both panes in Dual Pane) and every open folder in the tree."),
            .paragraph("Back/Forward and Up are per-tab. The **Go menu**'s **Recent Locations** submenu is an app-wide history of folders you've opened, newest first, shared across all tabs and windows \u{2014} pick one to jump there in the current tab. The submenu shows the 12 most recent; **Show All History\u{2026}** (**\u{2325}\u{2318}Y**) opens a searchable window with the full list, and **Clear Menu** empties it. How many are kept (default 20) is set in **Settings \u{25B8} General**. This is automatic and separate from **Pinned**, which is the handful of folders you've deliberately pinned to the sidebar."),
        ], seeAlso: [.destinations, .tabs]),

        HelpTopic(id: .fileList, title: "The File List", symbolName: "list.bullet.rectangle", section: .browsing, keywords: ["columns", "sort", "group", "icons", "grid", "hidden files", "folder size", "Quick Look", "Open With"], blocks: [
            .paragraph("Click a column header to sort by it. Right-click a header for a checklist of which columns to show \u{2014} Name is always present; Type, Date Modified/Created/Added, Date Last Opened, Size, Tags, and Extension are optional. Drag a header to reorder columns. Tags show as colored chips. **Where** shows each item's folder (it appears by itself in Recents and Shared)."),
            .paragraph("To see recent dates the way Finder shows them \u{2014} \u{201C}Today at 5:57 PM\u{201D}, \u{201C}Yesterday at 9:17 PM\u{201D} \u{2014} turn on **Settings \u{25B8} General \u{25B8} Friendly dates**. It applies to every date column, the Inspector, and search results; older dates are unchanged."),
            .paragraph("**Date Last Opened** normally shows when a file was last read by anything \u{2014} backups, searches, and apps checking a file all update it. To see when *you* last opened it, as Finder does, turn on **Settings \u{25B8} General \u{25B8} Date Last Opened: use Spotlight's date**; it asks Spotlight about every item as a folder loads, so big folders can open more slowly. A file Spotlight has never seen opened then shows no date."),
            .paragraph("The Context Bar's **Sort** menu combines Sort By (the same fields as the column headers) with **Group By** \u{2014} cluster the list by Name, Kind, Date Modified, Size, or Tags, or turn grouping off."),
            .paragraph("The search field at the top right filters the current folder's list by name as you type (subfolders aren't searched; for that, use **Advanced Search**). Press **/** from anywhere in the window to jump straight to it."),
            .paragraph("The **filter button** beside it (\u{2261}) narrows the list further: **Kind** (images, documents, video, \u{2026}), **Date Modified** (Today, This Week, This Month, This Year, or between dates), **Size**, **Extension**, **Tag**, files or folders only, and **Name Options** (starts with, ends with, regular expression, match case). Each filter shows as a **chip** under the Context Bar, with how many items match: click a chip to change it, its \u{2715} to remove it, **Clear** to remove them all. Filters stay on as you go from folder to folder \u{2014} handy for looking for the same thing in the next one \u{2014} until you clear them; each tab has its own."),
            .paragraph("**Search Subfolders** (in the chip row, or **View \u{25B8} Search Subfolders with This Filter**) takes the same filters into Advanced Search, searching this folder and everything inside it."),
            .paragraph("**\u{21E7}\u{2318}.** (View \u{25B8} Show Hidden Files, also in the Context Bar's **View** menu) toggles whether hidden (dot-prefixed) files are shown."),
            .paragraph("**View as Icons** (**\u{2318}1**) shows the folder as a grid of thumbnails (real previews of photos, PDFs, and documents) instead of a list; **as List** (**\u{2318}2**) switches back, as does the Grid/List switch in the Context Bar. OneRoot remembers the choice per folder, like Explorer and Finder: a Photos folder can stay in icons while everything else stays a list. The slider at the right of the status line sets the icon size. Everything else works the same in both views. (Sort applies in both; **Group By** only shows in the list.)"),
            .paragraph("Select something and press **Space** for Quick Look, or show the **Inspector** for a preview that stays open."),
            .heading("Folder sizes"),
            .paragraph("Folders show \u{201C}--\u{201D} in the Size column until their size is worked out, since that means adding up everything inside, which can take a while for big folders. Select folders and choose **Size** in the Context Bar (or right-click \u{25B8} **Calculate Size**) for just those, or choose **View \u{25B8} Calculate Folder Sizes** to size every folder in the current view once. To have every folder's size worked out as you browse, turn on **Settings \u{25B8} General \u{25B8} Always calculate folder sizes**. Sizes include everything inside, hidden files too, and update when something inside a folder changes. Sorting by Size uses them once they're known. Leaving the folder stops any calculation still in progress."),
            .heading("Open With"),
            .paragraph("Right-click a file and choose **Open With** to open it with a specific app instead of its default. Folders get an **Open With** menu too \u{2014} Terminal is always there, an **Editor** appears once one's configured in **Settings \u{25B8} Editor**, and anything else macOS already knows can open a folder is listed below those. Some editors (VS Code notably) open folders fine but don't tell macOS so, which is why the Editor setting exists."),
        ], seeAlso: [.contextBar, .inspector, .advancedSearch]),

        HelpTopic(id: .contextBar, title: "The Context Bar", symbolName: "rectangle.and.hand.point.up.left", section: .browsing, keywords: ["toolbar", "command bar", "actions", "ribbon", "paste", "quick actions", "selection"], blocks: [
            .paragraph("The **Context Bar** is the row under the path. It shows what you can do right now, so it changes with the selection."),
            .paragraph("**With nothing selected:**"),
            .bullets([
                "**New \u{25BE}** \u{2014} New Folder, New File, and New Folder and Open.",
                "**Sort \u{25BE}** \u{2014} sort by any column, and group by Name, Kind, Date Modified, Size, or Tags.",
                "**View \u{25BE}** \u{2014} the Inspector, Calculate Folder Sizes for this view, hidden files, and columns.",
                "**Grid/List** \u{2014} icons or a list, remembered per folder.",
                "**Dual Pane** \u{2014} a second folder beside this one.",
                "**More \u{25BE}** \u{2014} for the folder you're in: copy its path, open it in Terminal, add it to a Workspace.",
            ]),
            .paragraph("**With something selected**, New gives way to **N selected \u{2715}** and the selection's actions: Copy, Cut, Rename (several items: the batch Rename dialog), Share, **Size** (folders), Compress, Extract (archives), **Quick Actions \u{25BE}** (images, PDFs, text, Markdown, HTML), Copy Path, Terminal, and Trash. When the window is narrow, the labels step down to icons. **Esc**, **\u{2325}\u{2318}A** (Edit \u{25B8} Deselect All), or the **\u{2715}** clears the selection."),
            .paragraph("After you copy or cut files in OneRoot, a **Paste** chip appears at the right (\u{201C}Paste 2 items\u{201D}, or \u{201C}Move 2 items here\u{201D} after a Cut). \u{2318}V also pastes files copied in Finder or another app."),
            .paragraph("Everything in the Context Bar is also in the menus and in the right-click menu, so it's never the only way to do something."),
        ], seeAlso: [.fileOperations, .compress, .fileList]),

        HelpTopic(id: .inspector, title: "The Inspector", symbolName: "sidebar.right", section: .browsing, keywords: ["Properties", "Get Info", "preview pane", "details pane", "metadata", "tags", "permissions"], blocks: [
            .paragraph("The **Inspector** on the right shows what's selected without opening another window. Show or hide it with **\u{2325}\u{2318}I** (or **\u{21E7}\u{2318}P**), View \u{25B8} Inspector, or the button at the right of the tab strip; drag its divider to resize it. It's OneRoot's version of Explorer's Properties and macOS's Get Info."),
            .paragraph("For a selected item, from the top:"),
            .bullets([
                "A large **preview** \u{2014} a live Quick Look, with play controls for video and audio. For a Markdown file, **Raw | Rendered** above it switches between the text as written and the formatted page (raw by default; your choice is remembered). Links in the rendered page open in your browser.",
                "Its icon, name, kind, and size.",
                "**Open** \u{2014} opens it in its default app (a folder opens in place); the arrow beside it lists the other apps that can open it. Folders add Open in New Tab and Open in Terminal.",
                "**Share**, **Copy Path**, and **More** (Quick Look, Reveal in Finder, Open in Terminal, Rename, Move to Trash). For a folder, **New Tab** and **Pin** come first, and More adds **Add to Workspace**.",
            ]),
            .paragraph("Below them, three sections:"),
            .bullets([
                "**Details** \u{2014} kind, size (exact bytes and size on disk), a folder's item count and size (with **Calculate**), cloud status when macOS reports it, created/modified/last opened/added dates, where it is, what an alias points to, and tags.",
                "**More Info** \u{2014} what Spotlight knows: dimensions, resolution, duration, codecs, pages, title, authors, an app's version, where a download came from, and the Finder comment.",
                "**Permissions** \u{2014} the owner and group, what owner, group, and everyone may do, and whether it's locked.",
            ]),
            .paragraph("Each tab remembers which section it shows."),
            .heading("Tags"),
            .paragraph("The Tags row lets you change tags for a single item: click a tag's \u{2715} to remove it, or **+ Add Tag** for the standard color tags, the other tags used in this folder, or **New Tag\u{2026}**. The Tags column updates at once. Tag changes can't be undone with \u{2318}Z."),
            .paragraph("To tag **several items at once**, select them: the Inspector lists every tag they carry. One only some of them have shows \u{201C}2 of 5\u{201D} with **Add to All**; \u{2715} takes a tag off them all, and **Add Tag to All** puts one on them all. Each item keeps its other tags. The same is in the right-click menu's **Tags \u{25B8}**: a \u{2713} means every selected item has the tag, a dash that some do; choosing it puts it on them all, or takes it off if they all have it."),
            .heading("Several items, or none"),
            .paragraph("Select several items to see how many there are and their combined size, with Compress, Rename, and their tags (above). With nothing selected, the Inspector sums up the current folder."),
            .paragraph("The Inspector only shows what macOS really knows. Finder comments are read-only, because macOS only changes them reliably through Finder itself."),
        ], seeAlso: [.fileList, .workspaces]),

        HelpTopic(id: .fileOperations, title: "Copying, Moving & Renaming", symbolName: "doc.on.doc", section: .files, keywords: ["copy", "move", "paste", "cut", "undo", "redo", "rename", "batch rename", "Trash", "Recycle Bin", "delete", "restore", "put back", "drag", "conflict", "replace", "keep both", "merge", "alias", "right-drag", "copy name", "verify", "checksum", "queue", "one at a time"], blocks: [
            .shortcuts([
                ("\u{2318}C / \u{2318}X / \u{2318}V", "Copy / Cut / Paste \u{2014} across tabs, windows, and with Finder"),
                ("\u{2318}Z / \u{21E7}\u{2318}Z", "Undo / Redo the last file operation"),
                ("Return", "Rename the selected item"),
                ("\u{2318}\u{232B} or \u{232B}", "Move to Trash (or Restore / Delete Immediately while viewing the Trash)"),
                ("\u{21E7}\u{2318}N", "New Folder"),
                ("\u{2325}\u{2318}N", "New Folder and Open"),
                ("\u{2318}F", "New File"),
            ]),
            .paragraph("**Duplicate** (**\u{2318}D**, File \u{25B8} Duplicate, or the right-click menu) makes a copy of each selected item beside it, named like \u{201C}report (2).pdf\u{201D}, and selects the copies. \u{2318}Z removes them again."),
            .paragraph("When something with the same name is already there, OneRoot asks before it copies or moves anything: **Replace**, **Keep Both** (the new one gets \u{201C}(2)\u{201D}), or **Skip**. Replace moves the existing item to the **Trash**, so you can get it back (on a network share with no Trash, it's deleted)."),
            .paragraph("When a **folder** meets a folder of the same name, there's also **Merge**: the folder's contents go into the existing one, nothing already there is lost, and you're asked once about anything inside with the same name (folders inside can be merged too). Moving with Merge sends the emptied folder to the Trash; items you skipped stay where they were. Apps and other packages are never merged."),
            .paragraph("**Settings \u{25B8} General \u{25B8} Verify copies** checks every copy that goes to another disk: once copied, it's read back and compared with the original, byte for byte. A copy that doesn't match is removed and the item fails, with Retry; a move only deletes the original once its copy checks out. The progress shows \u{201C}Verifying the copy\u{2026}\u{201D} meanwhile. **Copy to the same disk one at a time** (on by default) makes a copy wait while another one is using the same disk, so they don't slow each other down; a waiting copy says so and has **Start Now**."),
            .paragraph("NFS shares can't store Mac metadata (Finder tags, \u{201C}Where from\u{201D}, quarantine flags) themselves, so macOS would write a hidden \u{201C}._\u{201D} file beside every item and lock it for each piece \u{2014} with many small files, that can double the time a copy takes. OneRoot leaves that metadata off copies to such shares; contents, permissions, and dates are copied as usual. Turn on **Settings \u{25B8} General \u{25B8} Keep Mac metadata on NFS shares** to keep it. Disks and SMB shares always get everything."),
            .paragraph("When several items collide, you're asked once for all of them, such as \u{201C}12 of 100 items already exist in \u{201C}Projects\u{201D}\u{201D}: **Replace All**, **Keep Both**, **Skip All**, or **Cancel** to copy nothing. **Choose for Each\u{2026}** lists every collision with both versions' dates and sizes, marking the newer one, and a Replace / Keep Both / Skip choice per item (they start at Skip). **Set all to** changes every row at once, and **Replace Older** replaces only the items whose existing copy is older."),
            .paragraph("Dragging a file copies it by default; hold **\u{2318}** while dropping to move instead. Dropping onto a folder (in the tree, the list, the path, or a tab) puts it inside that folder. \u{201C}New Folder Here,\u{201D} from a folder's context menu in the file list, creates the folder inside that item."),
            .paragraph("Hold **\u{2303} Control** as you let go of a drop in the file list or the folder hierarchy to choose what happens: **Move Here**, **Copy Here**, or **Make Alias Here** (a Finder alias named like \u{201C}report.pdf alias\u{201D}) \u{2014} like right-dragging on Windows. It works for files dragged in from Finder too, and the result can be undone."),
            .heading("Undo"),
            .paragraph("**Undo** (\u{2318}Z, or **Edit \u{25B8} Undo**) reverses the last copy, move, rename, new folder/file, or Move to Trash \u{2014} the menu item names exactly what it'll undo (e.g. **Undo Move of \u{201C}notes.txt\u{201D}**). **Redo** (\u{21E7}\u{2318}Z) puts it back. There's one undo history for the whole app, like Finder's, so it works no matter which window or tab the change was made in; it applies while the file list or sidebar has focus (in a text field, \u{2318}Z undoes typing instead). Undoing a copy moves the copy to the Trash rather than deleting it, and Undo never overwrites anything: if something new has taken the original spot since, it stops and says so. Undoing a Replace puts the new item in the Trash and brings the one it replaced back out of it. Delete Immediately and Empty Trash can't be undone."),
            .heading("Renaming several items at once"),
            .paragraph("Select them and press **Return** (or choose **Rename N Items\u{2026}** from the right-click or File menu). The dialog offers four rules: **Replace Text** (optionally case-sensitive, or a regular expression with $1/$2 for captured groups), **Add Text** before or after the name, **Format** (a base name plus a counter, with a start number and zero-padding, e.g. \u{201C}Vacation 001\u{201D}), and **Change Case**. File extensions are left alone unless you tick **Include file extensions**. A live preview shows every old \u{2192} new name and marks problems in red before anything changes: two items ending up with the same name, a name already taken in the folder, or an invalid name. Renaming is all-or-nothing (if one item fails, they're all put back), and **\u{2318}Z** undoes the whole batch in one step."),
            .heading("Trash"),
            .paragraph("Move to Trash always confirms first, however you ask for it. Some volumes \u{2014} many network shares \u{2014} have no Trash; for items there, OneRoot says so and offers **Delete Immediately** instead, which can\u{2019}t be undone. While viewing the Trash, items get **Restore** (back where OneRoot trashed them from) and **Delete Immediately** instead of the usual menu. **Empty Trash** is on the Trash's context menu in the sidebar."),
        ], seeAlso: [.fileOperationsCenter, .contextBar, .dualPane]),

        HelpTopic(id: .fileOperationsCenter, title: "File Operations", symbolName: "arrow.left.arrow.right", section: .files, keywords: ["progress", "copy dialog", "cancel", "retry", "errors", "failed", "history", "speed", "time remaining"], blocks: [
            .paragraph("The **File Operations** card in the tool row along the bottom (**\u{2303}\u{2318}B**, View \u{25B8} Tools Panel) follows every copy, move, compression, and extraction, plus Move to Trash, Delete Immediately, Restore, and Empty Trash."),
            .bullets([
                "**Active** \u{2014} what's running: bytes done of the total, speed, time remaining once it's steady, which item it's on, and where from and to, with a red **Cancel** button. Once pressed it turns into **Cancelling\u{2026}** while the item in progress winds down, so you can see it was taken. What's done stays, and can be undone. A cancelled or failed compress or extract leaves nothing half-made behind. When an operation can't report bytes, the card says so rather than guessing. Copies, moves to another drive, and compress and extract also get a **Pause** button (\u{23F8}): the work stops where it is, with nothing redone, and **Resume** (\u{25B6}) carries on from there. Time paused doesn't count toward speed or time remaining, and Cancel still works while paused. Quick operations (Trash, rename, a move on the same drive, Quick Actions) have no Pause.",
                "**Completed** \u{2014} what finished or was cancelled this session, with how much was done and how long it took. **Show** opens the destination in a new tab.",
                "**Errors** \u{2014} what failed, in red. **Details** shows how far it got and the system's reason. **Retry** (for copies, moves, and trashing) runs it again for only the items that didn't finish \u{2014} not the ones you chose to Skip.",
            ]),
            .paragraph("**Clear** empties the tab you're looking at; **\u{00D7}** removes a single entry. The list lasts until OneRoot quits."),
            .paragraph("Hiding the card never stops anything. While it's hidden, a small progress window appears for each operation instead, and a failure puts **N failed** in the status line \u{2014} click it to show the card's Errors."),
            .paragraph("Prefer no separate windows? Turn on **Settings \u{25B8} General \u{25B8} Show progress in the window**: starting a copy, move, compress, or extract then opens this card at the bottom of the window instead."),
            .paragraph("When an operation fails, a red banner above the status line says what went wrong, until you dismiss it (\u{2715}) or go to another folder; **Show Details** opens the card's Errors. VoiceOver reads the error out, and says when each operation finishes, is cancelled, or fails."),
        ], seeAlso: [.fileOperations, .compress]),

        HelpTopic(id: .compress, title: "Compress & Extract", symbolName: "archivebox", section: .files, keywords: ["zip", "unzip", "archive", "7z", "tar", "compressed folder"], blocks: [
            .paragraph("Select items and choose **Compress** in the Context Bar or the right-click menu. A single item keeps its own name (\u{201C}notes.txt\u{201D} \u{2192} \u{201C}notes.txt.zip\u{201D}); multiple items bundle into \u{201C}Archive.zip,\u{201D} matching Finder's own Compress. A new tab opens at the archive's destination once it's done, so you can see the result right away."),
            .paragraph("**Extract** appears for an archive in the Context Bar and its context menu, and double-clicking (or **\u{2318}O** on) an archive extracts it too \u{2014} everything happens in OneRoot itself rather than handing off to Archive Utility. The contents go into a new subfolder named after the archive. Which file types offer Extract depends on the engine selected in **Settings \u{25B8} Archives**: the default (Apple's built-in tool, the same one Finder's Compress uses) handles `.zip`; switching to p7zip also unlocks `.7z`, `.tar`, `.gz`, `.bz2`, and `.xz`. (**Open With** still offers other apps, if you want one of those instead.)"),
            .paragraph("**Settings \u{25B8} Archives** controls three things:"),
            .bullets([
                "**Compress Using** \u{2014} Apple's built-in tool (the default) or p7zip, if it's installed. Only engines actually found on your Mac are offered.",
                "**Format** \u{2014} Zip or 7z, once p7zip is selected (Apple's tool only makes zip files).",
                "**Save Archive** \u{2014} next to the original item (the default), always to one fixed folder, or ask for a destination every time.",
            ]),
            .paragraph("A name that already exists auto-numbers, the same \u{201C}(2)\u{201D}, \u{201C}(3)\u{201D} scheme OneRoot uses everywhere else. Progress shows in the File Operations card."),
        ], seeAlso: [.fileOperationsCenter, .settings]),

        HelpTopic(id: .quickActions, title: "Quick Actions", symbolName: "wand.and.stars", section: .files, keywords: ["resize", "convert", "image", "photo", "JPEG", "PNG", "HEIC", "EXIF", "GPS", "location", "strip metadata", "merge PDF", "combine PDF", "transform", "Word", "docx", "doc", "RTF", "to PDF", "Markdown", "md", "HTML", "web page", "txt"], blocks: [
            .paragraph("Select images, PDFs, or text, Markdown, or HTML files and **Quick Actions \u{25BE}** appears in the Context Bar, and as **Quick Actions \u{25B8}** in the right-click menu. It offers what applies to the whole selection; when only part of it fits (say, images and a text file), the action shows but is switched off, with the reason."),
            .bullets([
                "**Resize Images** \u{2014} by the longest side in pixels, or by a percentage. Images are never enlarged; ones already that small are skipped. Every frame of an animated GIF is kept.",
                "**Convert Images** \u{2014} to JPEG, PNG, HEIC, or TIFF (HEIC only where your Mac can write it), with a quality setting for JPEG and HEIC. Transparent areas become white in JPEG; formats that hold one image get the first frame of an animation.",
                "**Remove Metadata** \u{2014} a copy without the location, EXIF (camera, dates), IPTC, and XMP details. The orientation is kept so photos stay the right way up. JPEG, PNG, and TIFF are copied without re-compressing.",
                "**Text to Markdown** \u{2014} plain-text files (.txt, .text, .log, \u{2026}) as Markdown (.md). **Keep line breaks** keeps each line its own line; **Show symbols as written** stops \u{201C}# \u{201D}, \u{201C}- \u{201D}, and \u{201C}*\u{201D} from turning into headings, lists, and emphasis.",
                "**Markdown to HTML** \u{2014} a web page from a Markdown file, with headings, lists, tables, code, links, and images; optionally with simple styling that follows light and dark mode.",
                "**HTML to Markdown** \u{2014} keeps the text, headings, lists, links, images, code, and tables of a web page; layout, colors, scripts, and forms are dropped.",
                "**Convert to PDF** \u{2014} Word (.doc, .docx), RTF, OpenDocument text (.odt), and plain-text files as PDFs, laid out the way TextEdit prints them on your Mac's default paper size: text, fonts, styles, lists, tables, and pictures come through; Word's own page layout (headers and footers, columns, text boxes, exact page breaks) may not. Pages documents need Pages.",
                "**Combine into PDF** \u{2014} PDFs, images, and documents (converted as above) into one PDF, in an order you can change by dragging or with the arrows. PDFs keep their links and annotations; each image becomes a page its own size. Password-protected PDFs are left out (and shown as such).",
            ]),
            .paragraph("Every action opens a sheet first that previews exactly what will be written, and what's skipped and why \u{2014} for text conversions, with the first file's converted text. **Nothing is ever replaced**: new files go beside the originals (\u{201C}photo (resized).jpg\u{201D}, \u{201C}photo.png\u{201D}, \u{201C}photo (no metadata).jpg\u{201D}, \u{201C}Combined.pdf\u{201D}, \u{201C}notes.md\u{201D}), auto-numbered \u{201C}(2)\u{201D} if the name is taken. The new files are selected when they're done."),
            .paragraph("Progress, Cancel, and the result show in the File Operations card. **Edit \u{25B8} Undo** (\u{2318}Z) moves the new files to the Trash; the originals are never touched."),
        ], seeAlso: [.contextBar, .fileOperationsCenter, .compress]),

        HelpTopic(id: .advancedSearch, title: "Advanced Search", symbolName: "magnifyingglass", section: .files, keywords: ["find", "search", "grep", "regex", "Spotlight", "contents", "duplicates", "duplicate files", "flat view", "all files", "subfolders"], blocks: [
            .paragraph("**View \u{25B8} Show All Files in Subfolders** (also in the Context Bar's **View** menu) lists every file in the current folder and all the folders inside it in one list, with a **Where** column for the folder each is in \u{2014} sort, filter, preview, and copy them like any list. Folders themselves and the insides of apps aren't listed; very large folders stop at 50,000 files. It turns off when you go to another folder, or with **Show Folders**."),
            .paragraph("**View \u{25B8} Find Duplicates\u{2026}** (or **More \u{25B8} Find Duplicates\u{2026}**) finds files with identical contents in the current folder and everything inside it \u{2014} in both folders with Dual Pane on. Files are compared by size, then by their contents, so names don't matter; empty files, links, and the insides of apps are left out. The biggest savings come first. Tick the copies to throw away (**Mark All but Oldest/Newest** does it for every set) and **Move to Trash**; one copy of each set always stays, and Undo or Put Back brings them back."),
            .paragraph("The search field at the top right only filters the current folder's list by name \u{2014} it doesn't look inside subfolders. For a real recursive search, open **Advanced Search** (**\u{2325}\u{2318}/**, **View \u{25B8} Advanced Search**, or the last item of the filter menu \u{2261} beside the search field). It opens in its own window, so a long search over a whole drive doesn't block browsing."),
            .paragraph("Above the results, the same **filter chips** as in a folder show what's being searched for \u{2014} name or text, kind, dates, size, extension, tags, and hidden files or cloud storage when they're included. Remove one with its \u{2715} (a search in progress starts over without it), or use **Add Filter** for Kind, Date Modified ranges, and Tags, which only the chips offer."),
            .paragraph("A segmented control at the top switches between two modes:"),
            .bullets([
                "**Name & Metadata** \u{2014} match the name (Contains/Starts With/Ends With/Regex, with a case-sensitive toggle), plus optional extension, size-range, and date-modified-range filters. A **Folders / Files / Files & Folders** control narrows what kind of item to look for.",
                "**File Contents** \u{2014} grep-style: Contains/Regex against every line of candidate files, still narrowed by the same extension/size/date filters. Binary files and anything over 20 MB are skipped (and counted in the status line, not silently dropped), so a whole-volume content search doesn't stall on a video file or database.",
            ]),
            .paragraph("**Use Spotlight Index** (on by default) makes name searches near-instant: matches from macOS's Spotlight index appear right away, even across a whole drive, and then OneRoot keeps scanning every folder anyway to add anything Spotlight missed. The status line shows how many Spotlight found instantly and how many more the scan turned up. Press **Cancel** once you've seen what you need. Regex patterns, **Include Hidden Files**, File Contents searches, and locations Spotlight doesn't index (most network shares) skip Spotlight and just scan; the status line says why."),
            .paragraph("**Choose\u{2026}** sets the folder to search; **Entire Volume** jumps to the drive containing it. Results and a live \u{201C}N folders, N files scanned\u{201D} count appear as the search runs, and **Cancel** stops it promptly."),
            .paragraph("Double-click a folder result to open it **in OneRoot, in a new tab**; double-click a file to open it with its default app. Right-click a result for Open, **Open in OneRoot** (navigates your current tab), Reveal in Finder, and Copy Path."),
            .paragraph("**Saved Queries**, top-left, saves the current criteria (folder, mode, pattern, filters \u{2014} everything) under a name for one-click reuse later."),
            .paragraph("In Regex mode, a **Suggestions** menu next to the pattern field offers common patterns (image/video/audio/archive/document extensions, dates, email addresses, UUIDs, IP addresses, \u{2026}). Regex here means [ICU regular expressions](https://unicode-org.github.io/icu/userguide/strings/regexp.html), which differ slightly from `grep`'s in a few corners."),
            .paragraph("**Include Cloud Storage** (off by default) also searches iCloud Drive, Nextcloud, Google Drive, Dropbox, and other cloud folders when the search location contains them. Cloud files that aren't downloaded show up in name searches with a cloud-arrow icon. **A content search never opens a file that isn't downloaded**, so it can't make your Mac download anything; those files are left alone and counted in the status line."),
            .paragraph("**Show as Terminal Command\u{2026}** translates the current criteria into an approximate `find`/`grep` equivalent, with a one-click copy. **Export\u{2026}**, bottom-right once there are results, writes them out as CSV, plain text, Markdown, or a self-contained HTML page."),
        ], seeAlso: [.fileList]),

        HelpTopic(id: .visualize, title: "Visualize", symbolName: "chart.pie", section: .files, keywords: ["storage", "disk space", "treemap", "what's taking space", "large files", "usage"], blocks: [
            .paragraph("The **Visualize** card in the tool row along the bottom (**\u{2303}\u{2318}B**) shows what's taking up space in the folder you're in \u{2014} everything inside it, hidden files and package contents included \u{2014} and follows you as you browse. In Dual Pane it follows the pane you're working in."),
            .paragraph("Choose a breakdown at the top of the card:"),
            .bullets([
                "**Folders** \u{2014} a treemap of the folder's items (folders blue, files gray; items under 1% fold into \u{201C}N more items\u{201D}) beside the same items as a list with their sizes and shares. Click a folder to open it, or a file to select it in the list.",
                "**Types** \u{2014} images, video, audio, documents, archives, apps, code, and other.",
                "**Age** \u{2014} this week, this month, this year, or older, by last modified date.",
                "**Tags** \u{2014} each tag in its color, plus untagged.",
                "**Cloud** \u{2014} downloaded, cloud-only, and not in the cloud.",
            ]),
            .paragraph("For Types, Age, Tags, and Cloud, choose a group to see its largest files, and click one to find it in the list. Every chart has a labeled list beside it, so color never carries the meaning on its own."),
            .paragraph("Scanning runs in the background and updates the card as it goes. **Stop** keeps what's been counted so far; the \u{21BB} button scans again. Going to another folder stops a scan in progress, and folders scanned earlier in the session show again at once. Nothing is scanned while the card is hidden."),
            .paragraph("Symbolic links aren't followed, an app or other package counts as one item, folders that can't be read are skipped and counted (\u{201C}N couldn't be read\u{201D}), and cloud files are measured without downloading anything."),
        ], seeAlso: [.fileOperationsCenter, .fileList]),

        HelpTopic(id: .networkShares, title: "Network Shares", symbolName: "network", section: .connecting, keywords: ["smb", "afp", "nfs", "server", "map network drive", "NAS"], blocks: [
            .paragraph("**\u{2318}K** (Go \u{25B8} Connect to Server\u{2026}), or the gear on the startup-disk card at the bottom of the sidebar, opens a dialog for `smb://`, `afp://`, or `nfs://` addresses \u{2014} the same thing typing one of those directly into the path does."),
            .paragraph("Credentials can be saved to the Keychain and are offered back automatically next time you connect to that host. Save an address as a favorite server for one-click reconnecting."),
            .paragraph("A mounted share shows up under **Locations** in the sidebar automatically. To disconnect, click the \u{23CF} button beside it or press **\u{2318}J** while you're in it."),
        ], seeAlso: [.destinations, .copyViaSSH]),

        HelpTopic(id: .copyViaSSH, title: "Copy via SSH", symbolName: "lock.shield", section: .connecting, keywords: ["scp", "ssh", "remote", "upload", "key"], blocks: [
            .paragraph("Right-click one or more files and choose **Copy via SSH\u{2026}** to `scp` them to a remote host."),
            .paragraph("The dialog can save destinations (host, port, username, remote path, and an optional private key) for reuse \u{2014} the same list is also editable from **Settings \u{25B8} SSH**."),
            .paragraph("If you point it at a private key (picked up from `~/.ssh` when there is one), that's used instead of a password. If the server doesn't have that key yet, **Install Key on Server\u{2026}** in the destination editor puts it there via `ssh-copy-id`, using your account password just for that one step \u{2014} that password is never saved."),
            .paragraph("Because a saved destination can carry a stored password or key passphrase, choosing **Copy via SSH\u{2026}** asks for Touch ID or your Mac password first. This can be turned off in **Settings \u{25B8} SSH**."),
        ], seeAlso: [.networkShares, .settings]),

        HelpTopic(id: .terminal, title: "Terminal Integration", symbolName: "terminal", section: .connecting, keywords: ["shell", "command line", "iTerm", "Command Prompt", "PowerShell"], blocks: [
            .paragraph("\u{201C}Open in Terminal,\u{201D} from the sidebar, the file list's context menu, the Inspector, or the Context Bar, opens a shell at that folder (or, for a selected file, its enclosing folder)."),
            .paragraph("By default this uses Terminal.app. To use something else, set it in **Settings \u{25B8} Terminal**. Most terminal apps (Terminal.app, iTerm2, \u{2026}) work automatically; a few others (Tabby, kitty, Alacritty) need an extra \u{201C}Open-Folder Argument\u{201D} \u{2014} check that app's own documentation for the right value if the default doesn't work."),
        ], seeAlso: [.settings]),

        HelpTopic(id: .themes, title: "Themes", symbolName: "paintpalette", section: .customizing, keywords: ["appearance", "dark mode", "light mode", "colors", "Catppuccin", "Gruvbox", "Nord", "Tokyo Night"], blocks: [
            .paragraph("**Settings \u{25B8} Appearance** picks a theme. **OneRoot (Automatic)**, the default, is the OneRoot look \u{2014} white cards over a translucent window, blue folders \u{2014} in light or dark, following your Mac. **OneRoot Light** and **OneRoot Dark** keep one or the other. **macOS (Automatic)** is the plain macOS look with burgundy folders; the rest are Catppuccin (Latte, Frapp\u{00E9}, Macchiato, Mocha), Gruvbox (Dark, Light), Nord, and Tokyo Night (Night, Storm, Day), using each project's published colors."),
            .paragraph("A theme sets backgrounds, text, selection, the accent, and the colors of OneRoot's own icons (the sidebar's, the icon view's folders, and the toolbar's). File-type icons, like a document's or a photo's, come from macOS and keep their own look. A color that would be too faint on a theme's own background is darkened or lightened just enough to read."),
        ], seeAlso: [.settings]),

        HelpTopic(id: .settings, title: "Settings", symbolName: "gearshape", section: .customizing, keywords: ["preferences", "options", "update", "check for updates", "new version"], blocks: [
            .paragraph("Open Settings with **\u{2318},**. Categories are listed in a sidebar, System Settings-style:"),
            .bullets([
                "**General** \u{2014} whether to reopen last session's windows and tabs, whether closing a window's last tab asks first, **Always calculate folder sizes**, **Show progress in the window**, **Friendly dates**, **Date Last Opened: use Spotlight's date**, whether the address bar shows a clickable path or a plain text field, and how many folders the Go menu's **Recent Locations** keeps (20 by default), with a button to clear them.",
                "**General**, file operations and updates \u{2014} **Verify copies**, **Copy to the same disk one at a time**, **Keep Mac metadata on NFS shares** (see **Copying, Moving & Renaming**), and **Check for updates automatically** (off by default): once a day OneRoot asks GitHub whether a newer version is out and shows its notes; it never downloads or installs anything by itself. **OneRoot \u{25B8} Check for Updates\u{2026}** checks any time, and **Skip This Version** stops reminders about that one.",
                "**Appearance** \u{2014} the theme. See **Themes**.",
                "**Terminal** \u{2014} which app \u{201C}Open in Terminal\u{201D} launches, and the pinned Terminal entry in a folder's **Open With** menu.",
                "**Editor** \u{2014} which app the pinned **Editor** entry in a folder's Open With menu launches. Off until you pick one.",
                "**SSH** \u{2014} manage saved \u{201C}Copy via SSH\u{201D} destinations, and turn the Touch ID/password prompt on or off.",
                "**Archives** \u{2014} which engine and format Compress uses, and where it saves its output. See **Compress & Extract**.",
            ]),
            .paragraph("The **?** button in each pane opens the Help topic for it."),
        ], seeAlso: [.themes, .terminal, .compress, .copyViaSSH]),

        HelpTopic(id: .shortcuts, title: "Keyboard Shortcuts", symbolName: "keyboard", section: .customizing, keywords: ["keys", "hotkeys", "cheat sheet"], blocks: [
            .paragraph("**\u{2318}B** shows this list as a popover over the current window."),
        ] + KeyboardShortcutReference.sections.flatMap { section in
            [HelpBlock.heading(section.title), .shortcuts(section.shortcuts)]
        }, seeAlso: [.comingFromWindows]),
    ]
}
