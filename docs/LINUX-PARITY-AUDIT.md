# Linux vs Mac parity audit

First written 2026-11-06 (Linux 0.2.0), refreshed 2026-11-07 after the L11 series and the follow-up batch. Method: the Mac's menu commands, shortcuts, toolbar, tab bar, path bar, file-list context menu, Settings and views were compared with the Linux app, with a code check for each gap. It is a catalog comparison, not a pixel-by-pixel review. `Linux/PARITY.md` has the per-feature detail and where the code is.

## What is left

| Item | Status |
|---|---|
| Drag a tab into another window, or out to make a new window | **Half done.** Dropping a tab on another window's tab strip moves it there with its folder, history and sort (the source releases the tab, the destination rebuilds it; an emptied window closes). The transfer was checked on screen by triggering AdwTabView's own page transfer, **not by a real pointer drag**: the headless harness has no window manager and the drag never reached the second window. **Not done:** dragging a tab out of the strip to make a new window (needs `create-window`). **Move Tab to New Window** covers that |
| Drag a pane header out of the window to open it on its own | **Not done**, same reason. Swapping panes by dragging a header onto the other pane works |
| Drag a column header to reorder | Works on X11; **reported not working on Wayland (GTK 4.24)**, cause not found. Move Left / Move Right in the header menu does the same |
| Inspector previews of other types (PDF, audio, video) | Not done: images, text and Markdown only (needs a renderer library) |
| Toolbar search field | **Design choice (yours):** Linux has the filter bar under the path bar (Ctrl+F) instead |
| Share button / sheet | Platform: no Linux equivalent |
| "Coming from Windows" Help topic | Left out on purpose (public copy doesn't pitch OneRoot that way) |

## Done since the audit began

Tab menu, Duplicate / Move / Close Others, tab switching keys, All Tabs list for overflowing tabs; Dual Pane headers, Swap Panes (button, shortcut, header drag), Compare Panes; path bar subfolder menus, crumb menu and drops, history menus, Reload, Recent Locations, History window; Group by, visible and reorderable columns, type-to-select, Quick Look, Show All Files in Subfolders, Esc and Deselect All, Get Info, New Folder Here, Copy Names without Extensions, Show in File Manager, Open in Editor; Eject / Disconnect; Collapse All / Expand Top Level, Tools Panel, Reset Window Layout; Visualize treemap and stacked-bar charts; Workspace icon choice; Advanced Search regex suggestions and between-dates filter; file-type icons in Find Duplicates; Grid icon-size slider; shortcut quick popover; Markdown preview; Settings for address bar style and editor; sidebar menu (Eject, Empty Trash, Copy Path, Show in File Manager, Open in Terminal); Empty Trash; Help topics and shortcut list brought up to date.

## Checked against the Mac code and found not to exist there

Spring-loaded folders while dragging; reordering pinned sidebar items; reordering Workspaces in the sidebar (only a Workspace's own folders reorder, which Linux has).

## Platform-only (will not match)

iCloud and the Shared location, Touch ID for SSH, Full Disk Access onboarding, Browse Package Contents, Share sheet, Spotlight dates, Mac metadata on NFS, floating File Operations windows. Window position isn't restored (GTK4 on Wayland). Return renames on the Mac; F2 does on Linux (desktop convention, deliberate).
