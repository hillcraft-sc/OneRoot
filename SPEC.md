# Application Specification — "OneRoot"

A simple, Windows-File-Explorer-style file manager for macOS. Built to replace
Finder for day-to-day navigation without the quirks of Finder or the bloat of
existing open-source alternatives.

> **Name:** `OneRoot`. Rename freely; it appears only in the bundle
> identifier and display name, both defined in one place.

---

## 1. Product Vision

A fast, native macOS file manager that behaves the way Windows File Explorer
does, keeping only what makes navigation quick and predictable:

- A persistent **folder tree on the left** rooted at the Mac's drives, expandable
  all the way down.
- **Mounted volumes** (USB drives, external disks, disk images) appear and
  disappear in the tree automatically.
- **Network shares** (SMB/AFP) can be mounted from within the app and appear in
  the tree.
- **Tabs** so multiple locations can be open at once.
- A **typable address bar** ("go to path") like Windows, not Finder's Go-to-Folder
  sheet or the ⌘G modal.
- Deliberately **minimal**: no gimmicks, no gallery/column-view zoo, no clutter.
- **Extensible**: a clean architecture so new features can be added later, one at
  a time, with Claude Code.

### Non-goals (v1)
- Not a Finder plugin or a Finder-syncing tool; it is a standalone app.
- Not aiming for Mac App Store distribution (see Sandboxing below).
- No cloud-service integrations, no built-in terminal, no theming engine in v1.

---

## 2. Target Platform & Tooling

| Item | Decision |
|---|---|
| OS target | macOS 14 (Sonoma) or later |
| Language | Swift 5.9+ |
| UI | SwiftUI app shell + AppKit (`NSViewRepresentable`) for the tree and list |
| Build | Xcode 15+, standard `.xcodeproj` (no SwiftPM app target needed for v1) |
| Dependencies | **None** in v1. Everything uses system frameworks. |
| Distribution | Direct download outside the Mac App Store (decided 2026-10-30). Releases: Developer ID signing + Apple notarization, as a stapled DMG built by `Scripts/release.sh`. Debug builds: development signing. License: GPL-3.0-only (name and icon reserved, see TRADEMARKS.md). |

### Why SwiftUI + AppKit hybrid
SwiftUI is ideal for the window chrome, tabs, toolbar, and address bar, and keeps
the code approachable for incremental development. But a file tree and a file list
need to scale to thousands of items with lazy loading, and AppKit's
`NSOutlineView` and `NSTableView` are the proven, high-performance controls for
exactly this. The tree and the file list are each wrapped in an
`NSViewRepresentable` so they live inside the SwiftUI layout while keeping AppKit's
performance. This is the standard pattern for serious macOS file UIs.

---

## 3. The Sandboxing Decision (important)

A file manager that browses the **entire disk** and mounts network shares does not
fit comfortably inside the macOS App Sandbox — the sandbox is designed to stop
apps from doing precisely that without per-folder user consent.

**Decision for v1: ship non-sandboxed and request Full Disk Access.**

- `App Sandbox` capability: **OFF**.
- On first launch, detect whether the app has Full Disk Access. If not, show a
  friendly explainer screen with a button that deep-links to
  **System Settings → Privacy & Security → Full Disk Access**
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`),
  then prompt the user to add and enable the app.
- Debug builds are signed for development. Releases are signed with the
  owner's Developer ID (team 6S92GA582Q) and notarized by Apple
  (`Scripts/release.sh`), so a downloaded copy passes Gatekeeper without
  workarounds and keeps one stable code identity (Full Disk Access then
  survives updates).

> If App Store distribution ever becomes a goal, the tree would have to be rebuilt
> around security-scoped bookmarks and user-selected folders, which is a large
> change. That is explicitly deferred.

---

## 4. Layout & UI

```
┌────────────────────────────────────────────────────────────────────┐
│  [Tab: Macintosh HD] [Tab: Downloads] [ + ]                         │  ← Tab bar
├────────────────────────────────────────────────────────────────────┤
│  ◀ ▶  ▲   [ /Users/eric/Documents/Projects              ] [Go]  🔍  │  ← Toolbar + address bar
├──────────────────┬─────────────────────────────────────────────────┤
│ ▸ Macintosh HD   │  Name            Date Modified   Size    Kind    │
│   ▸ Applications │  ▸ src           Jul 10, 2026     --      Folder  │
│   ▾ Users        │  ▸ assets        Jul 09, 2026     --      Folder  │
│     ▾ eric       │    README.md     Jul 11, 2026    2 KB    Markdown │
│       ▸ Documents│    build.sh      Jul 08, 2026    1 KB    Script   │
│ ▸ USB DRIVE      │                                                   │  ← Tree (left)   File list (right)
│ ▸ 192.168.1.5    │                                                   │
│   [+ Connect...] │                                                   │
├──────────────────┴─────────────────────────────────────────────────┤
│  4 items, 2 folders            120 GB available on Macintosh HD      │  ← Status bar
└────────────────────────────────────────────────────────────────────┘
```

> **Superseded layout (UX Phase 1):** the single sidebar tree below is now
> split into a shallow SwiftUI destinations sidebar and a folder-hierarchy
> pane (the same `NSOutlineView`) rooted at the active tab's destination,
> with a collapsible Inspector on the right and a status bar that opens into
> a tools panel (File Operations, Dual Pane). See README.md "UX Phase 1" and
> CLAUDE.md §6. §4.1 describes the original v1 tree.

### 4.1 Sidebar folder tree (left)
- Root nodes: each mounted volume (internal disk, external/USB, disk images) plus a
  section for connected network shares.
- Expandable to arbitrary depth. **Children load lazily** when a node is expanded.
- Selecting a node loads that folder in the file list and updates the address bar.
- Volumes appear/disappear live via mount/unmount notifications.
- A **"Connect to Server…"** action lives at the bottom of the network section.
- Right-click context menu: Open in New Tab, Reveal in file list, Eject (for
  volumes/shares), Copy Path.

### 4.2 File list (right, main pane)
- Detail/list view: **Name, Date Modified, Size, Kind** columns, sortable by
  clicking headers. (List view only in v1 — no icon/column/gallery views.)
- Double-click a folder → navigates into it (updates list, address bar, and
  syncs/expands the tree selection).
- Double-click a file → opens with the default app (`NSWorkspace.open`).
- Native file icons via `NSWorkspace.shared.icon(forFile:)`.
- Multi-select, keyboard navigation (arrows, Return to open, ⌫ / ⌘⌫ to Trash).
- Context menu: Open, Open With…, Quick Look, Copy, Cut, Paste, Rename, Move to
  Trash, Get Info, Copy Path, New Folder.

### 4.3 Address bar (Windows-style)
- An always-visible, editable text field showing the current path.
- Typing a path and pressing **Return** (or clicking **Go**) navigates there.
- Accepts `/absolute/paths`, `~` expansion, and `smb://host/share` URLs.
- Invalid path → inline red validation, no navigation.
- Optional (v1.1): clickable breadcrumb segments layered over the same control.

### 4.4 Toolbar
- **Back / Forward** (per-tab history stack).
- **Up** (parent directory).
- Address bar + **Go** button.
- **Search** field (filters current folder by name in v1; recursive search is a
  later feature).

### 4.5 Tabs
- New Tab (⌘T), Close Tab (⌘W), Cmd-click a folder to open in a new tab.
- Each tab owns its own current path, navigation history, sort order, and
  selection. The sidebar is shared window chrome.

### 4.6 Status bar
- Item count and selection count; free space on the current volume.

---

## 5. Feature Areas & the APIs Behind Them

This section is the technical map. Each feature names the concrete macOS API so
implementation is unambiguous.

### 5.1 File system model & browsing
- `FileManager` for directory contents
  (`contentsOfDirectory(at:includingPropertiesForKeys:options:)`).
- Use `URLResourceKey` prefetch (`.isDirectoryKey`, `.fileSizeKey`,
  `.contentModificationDateKey`, `.localizedTypeDescriptionKey`,
  `.effectiveIconKey`) for fast column population.
- Lazy children: a tree node fetches its children only on first expansion.

### 5.2 Volume / USB detection
- Enumerate at launch: `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:options:)`.
- Live updates via `NSWorkspace.shared.notificationCenter`:
  `didMountNotification`, `didUnmountNotification`, `didRenameVolumeNotification`.
- Volume metadata via `URLResourceKey` (`.volumeNameKey`,
  `.volumeIsRemovableKey`, `.volumeIsEjectableKey`,
  `.volumeAvailableCapacityKey`, `.volumeTotalCapacityKey`).
- Eject via `NSWorkspace.shared.unmountAndEjectDevice(at:)`.

### 5.3 Network shares (mount from the app)
- "Connect to Server…" dialog collects a URL (`smb://host/share`,
  `afp://…`, `nfs://…`) and optional credentials.
- Mount with the **NetFS** framework: `NetFSMountURLSync(...)` (or its async
  variant) — this is exactly what Finder's ⌘K uses under the hood.
- On success the mount point appears under `/Volumes` and is picked up by the same
  mount-notification path as USB drives, so it shows in the tree automatically.
- Credentials optionally stored in the **Keychain** (`Security` framework) for
  reconnect.

### 5.4 Live folder updates
- Watch the currently displayed folder for external changes with **FSEvents**
  (`FSEventStreamCreate`) or a `DispatchSource` `.vnode` watcher, and refresh the
  file list when files change on disk.

### 5.5 File operations
- Copy / Move / Rename / New Folder via `FileManager`.
- Delete → **Move to Trash** via `FileManager.trashItem(at:resultingItemURL:)`.
- Copy/Cut/Paste through `NSPasteboard` with file URLs.
- Long operations run off the main thread with progress reporting; conflicts
  (name collisions) are found before anything is copied and asked about
  once — Replace / Keep Both / Skip for one item, or for several: Replace
  All / Keep Both / Skip All / Cancel / Choose for Each. Replace moves the
  existing item to the Trash (deleted only where the volume has no Trash).

### 5.6 Previews & icons
- **Quick Look** via `QLPreviewPanel` (spacebar), matching Finder behavior.
- Icons from `NSWorkspace.shared.icon(forFile:)` / `.icon(for: UTType)`.

### 5.7 Open / Reveal
- Open with default app: `NSWorkspace.shared.open(_:)`.
- "Open With…" enumerates handlers via `NSWorkspace.shared.urlsForApplications(toOpen:)`.

---

## 6. Architecture

MVVM, with a thin service layer over the file system so UI code never touches
`FileManager` directly. This is what makes the app easy to extend later.

```
OneRoot/
├─ App/
│  ├─ OneRootApp.swift             // @main, window/scene setup
│  └─ AppConfig.swift              // display name, bundle id, constants
├─ Models/
│  ├─ FileNode.swift               // a file/folder: url, name, isDir, size, dates, lazy children
│  ├─ VolumeInfo.swift             // a mounted volume / share
│  └─ Tab.swift                    // current path, history stack, sort state
├─ Services/                       // NO SwiftUI/AppKit imports here
│  ├─ FileSystemService.swift      // list, copy, move, rename, trash, new folder
│  ├─ VolumeService.swift          // enumerate + mount/unmount notifications
│  ├─ NetworkShareService.swift    // NetFS mount, Keychain credentials
│  └─ FileWatcher.swift            // FSEvents wrapper -> Combine publisher
├─ ViewModels/
│  ├─ DestinationsViewModel.swift  // global destinations (UX Phase 1)
│  ├─ FolderHierarchyViewModel.swift // was SidebarViewModel
│  ├─ FileListViewModel.swift
│  └─ WindowViewModel.swift        // owns tabs, active tab, shared services
├─ Views/
│  ├─ MainWindowView.swift         // splits sidebar | (toolbar + list)
│  ├─ Destinations/DestinationsSidebarView.swift
│  ├─ Shell/                       // PaneSplitView, ContextualWorkspaceView
│  ├─ Inspector/InspectorContainerView.swift
│  ├─ Sidebar/
│  │  ├─ FolderHierarchyView.swift // NSViewRepresentable
│  │  └─ FolderOutlineView.swift   // NSOutlineView controller
│  ├─ FileList/
│  │  ├─ FileListView.swift        // NSViewRepresentable
│  │  └─ FileTableController.swift // NSTableView controller
│  ├─ Toolbar/
│  │  ├─ AddressBarView.swift
│  │  └─ NavigationButtons.swift
│  ├─ Tabs/TabBarView.swift
│  └─ Dialogs/ConnectToServerView.swift
└─ Resources/
   └─ Assets.xcassets, Info.plist
```

### Design rules
- **Services are UI-agnostic and independently testable.** No view or view model
  reaches into `FileManager` directly.
- **Async** file work uses Swift Concurrency (`async`/`await`, `Task`); the main
  actor only touches UI.
- Services expose results as `async` functions and/or Combine publishers so view
  models stay thin.
- New features should be addable as a new Service + ViewModel + View without
  touching unrelated code.

---

## 7. Permissions & Info.plist

- **Full Disk Access**: not a plist entry — it is a user-granted TCC permission.
  Guide the user to grant it (see §3).
- If any code path triggers TCC prompts for Desktop/Documents/Downloads, include
  the matching usage-description keys
  (`NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`,
  `NSDownloadsFolderUsageDescription`, `NSNetworkVolumesUsageDescription`,
  `NSRemovableVolumesUsageDescription`) with clear strings.
- Hardened Runtime **ON** (required for notarization). Its one exception,
  in `OneRoot/OneRoot.entitlements`: `com.apple.security.automation.apple-events`,
  so Open in Terminal can send Terminal its AppleScript.

---

## 8. Roadmap (build order)

**Phase 1 — Skeleton**
Xcode project, non-sandboxed config, single window, MVVM scaffolding, empty
sidebar/list/toolbar wired together.

**Phase 2 — Browse**
Sidebar tree rooted at Macintosh HD with lazy expansion; file list with sortable
Name/Date/Size/Kind columns; double-click navigation; tree↔list sync.

**Phase 3 — Address bar & history**
Typable path navigation, Back/Forward/Up, ~ and smb:// handling.

**Phase 4 — Volumes**
USB/external volume detection, live mount/unmount updates, eject.

**Phase 5 — Tabs**
Multiple tabs, per-tab path + history, new-tab-from-folder.

**Phase 6 — Network shares**
Connect-to-Server dialog, NetFS mount, Keychain credentials.

**Phase 7 — File operations**
Copy/Cut/Paste, rename, new folder, move to Trash, Quick Look, context menus,
FSEvents live refresh.

**Phase 8 — Polish**
Full Disk Access onboarding, keyboard shortcut pass. No signing/notarization
work — personal-team signing via Xcode is already sufficient.

**Phase 9 — Advanced Search** (post-v1)
A separate "Advanced Search" window (⌘⌥/, or the toolbar's search-circle
button) for recursive search over a chosen folder or an entire volume —
distinct from the toolbar's `SearchFieldView`, which only filters the current
folder's list. Two modes, switched with a segmented control:
- **Name & Metadata** — name pattern (Contains/Starts With/Ends With/Regex,
  case-sensitive toggle) plus extension, size range, date-modified range, and
  include-hidden filters.
- **File Contents** — grep-style line search (Contains/Regex) through
  candidate files' text, still narrowed by the same extension/size/date
  filters; binary files and files over 20 MB are skipped automatically and
  counted, not silently dropped.

`SearchService` streams `SearchEvent`s (`.matched`/`.progress`) via
`AsyncThrowingStream` as the walk proceeds, so results and live
folders/files-scanned counts appear incrementally instead of after a long
silent pause — this is also what makes Cancel actually respond quickly.
Results show Open / Open in OneRoot / Reveal in Finder / Copy Path via
context menu; "Open in OneRoot" reaches back into whichever main window was
most recently active and navigates it to the result.
**Verify:** search a large folder by name and by regex; switch to File
Contents and grep for text across nested files; confirm progress counts
update live and Cancel stops promptly; confirm Open in OneRoot and Reveal in
Finder both land on the right item.

### Later ideas (post-v1, add incrementally)
Breadcrumb bar, favorites/pinned locations, dual-pane mode, tag/color labels,
batch rename, archive (zip) support, dark-mode-tuned icons, per-folder view
settings.

---

## 9. Acceptance Criteria (v1 "done")

1. Launches to a window with a folder tree showing Macintosh HD and any mounted
   volumes.
2. The tree expands to arbitrary depth and stays in sync with the file list.
3. The file list shows Name/Date/Size/Kind, sortable, with native icons.
4. Typing a path in the address bar and pressing Return navigates there.
5. Back/Forward/Up work per tab.
6. Plugging in a USB drive makes it appear in the tree within a couple seconds;
   ejecting removes it.
7. "Connect to Server…" mounts an SMB share that then appears in the tree.
8. Tabs open, close, and each keep independent location + history.
9. Copy/paste, rename, new folder, and move-to-Trash all work.
10. Quick Look opens on spacebar.
11. App builds and launches from Xcode with free personal-team signing, no
    Gatekeeper warnings, after Full Disk Access is granted.
