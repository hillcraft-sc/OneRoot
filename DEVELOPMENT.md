# OneRoot

A Finder replacement for macOS that feels familiar to Windows users: a
destinations sidebar, a folder hierarchy rooted where you're working, a
sortable file list, an Inspector, a typable address bar, tabs, and native
volume/network-share support. See `SPEC.md` for the
full product spec and `CLAUDE.md` for how this project is being built
phase by phase.

## License

OneRoot is free software, licensed under the
[GNU General Public License v3.0 only](LICENSE) (GPL-3.0-only). You may use,
study, modify, and redistribute it under those terms; modified versions must
stay under the GPL with their source available.

The **"OneRoot" name and the app icon are not covered by the GPL.** They
identify the official project, so a modified version must use a different name
and icon. See [TRADEMARKS.md](TRADEMARKS.md).

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) (contributors
certify their work with a DCO `Signed-off-by` line). Security issues:
[SECURITY.md](SECURITY.md). Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Build

1. Install Xcode 15+ (free, Mac App Store) if you haven't already.
2. Open `OneRoot.xcodeproj` in Xcode.
3. Select the `OneRoot` scheme and press ⌘R to build and run.

No third-party dependencies — system frameworks only. Debug builds from Xcode
are signed for development; releases are signed with Developer ID and
notarized by Apple (see "Cutting a new release" below).

## Download

Pre-built copies are published as
[Releases on GitHub](https://github.com/hillcraft-sc/OneRoot/releases):
grab the latest `OneRoot-x.y.z.dmg`, open it, and drag `OneRoot` onto the
Applications folder beside it.

Releases are signed with Developer ID and notarized by Apple, so OneRoot opens
like any other downloaded app: macOS asks once to confirm opening an app from
the internet, and that's it. On first launch OneRoot walks you through
granting Full Disk Access; because every release carries the same signature,
that permission survives updates.

### Cutting a new release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in Xcode.
2. Build, sign, notarize, and staple the disk image:
   ```
   Scripts/release.sh
   ```
   It archives a Release build, exports it with the Developer ID certificate,
   wraps it in `build/release/OneRoot-x.y.z.dmg` (with an Applications link),
   submits that to Apple's notary service and waits, staples the ticket, and
   checks the result with Gatekeeper (`spctl`). One-time setup per Mac is in
   the script's header: the *Developer ID Application* certificate and the
   `OneRoot` notarytool keychain profile.
3. Write the release notes in `Public/notes/x.y.z.md`, then publish:
   ```
   Scripts/publish-github.sh x.y.z
   ```
   Releases are public on [GitHub](https://github.com/hillcraft-sc/OneRoot),
   in a repo that holds releases only: it gets `Public/README.md`, the icon,
   LICENSE, and `Install OneRoot.txt`, and each release gets the notarized
   DMG. The source and issues stay here on Gitea.
4. Tag the version here too:
   ```
   git tag vx.y.z
   git push origin vx.y.z
   ```

## Current status

**Phase 1 — Skeleton: done.**
**Phase 2 — Browse: done.**
**Phase 3 — Address bar & history: done.**
**Phase 4 — Volumes: done.**
**Phase 5 — Tabs: done.**
**Phase 6 — Network shares: done.**
**Phase 7 — File operations: done.**
**Phase 8 — Polish: done.**
**v1: done** — all acceptance criteria in SPEC.md §9 verified.
**Phase 9 — Advanced Search: done** (post-v1, see SPEC.md §8).

- MVVM folder structure in place (`App/`, `Models/`, `Services/`,
  `ViewModels/`, `Views/…`, `Resources/`).
- App Sandbox capability off, Hardened Runtime on.
- `FileSystemService` lists directories with resource-key prefetch
  (name, size, modification date, kind) off the main thread.
- `FolderOutlineView` (`NSOutlineView`): sidebar tree rooted at the boot
  volume, lazy child loading on expand, native icons.
- `FileTableController` (`NSTableView`): sortable by clicking headers,
  native icons, user-customizable columns (see "Customizable file list
  columns" below).
- Selecting a tree node loads that folder in the list; double-clicking a
  folder in the list navigates into it and syncs/expands the tree selection.
- Double-clicking a file opens it with the default app.
- `AddressBarView`: editable path field, Return/Go to navigate. Accepts
  absolute paths, `~` expansion, and `smb://`/`afp://`/`nfs://` addresses
  (mounted on the fly, using any saved Keychain credentials for that host).
  Invalid input shows inline red text instead of navigating.
- `NavigationButtons`: Back/Forward/Up, backed by a per-tab history stack
  on `FileListViewModel` (works no matter how you navigated — tree, list,
  address bar, or the buttons themselves).
- `FileSystemServiceTests`, `PathResolverTests`, `FileListViewModelTests`
  cover directory listing, path validation/expansion, and back/forward/up
  history behavior.
- `VolumeService`: enumerates mounted volumes and publishes live updates via
  `NSWorkspace` mount/unmount/rename notifications.
- The sidebar tree now shows one root per mounted volume (internal disk,
  external/USB, disk images) instead of a single "/" root — plugging in a
  drive adds it live; unmounting removes it. Existing root nodes keep their
  cached children/expansion state across updates (only volumes that actually
  came or went cause a full reload).
- Right-click an ejectable volume in the sidebar for an **Eject** menu item;
  failures show an alert instead of failing silently.
- Fixed a bug from Phase 2 where the sidebar's root row got permanently
  stuck on "Loading…" — the outline view's data source conflated "the top
  level" with "the root's own children," so the loaded data was applied to
  a row that was never actually displayed.
- `VolumeServiceTests`, `SidebarViewModelTests` cover volume enumeration and
  the root-node identity-preserving diff logic (via a fake volume provider,
  not live system state).
- `WindowViewModel` owns an ordered list of tabs and the active tab; each
  `Tab` has its own `FileListViewModel`, so path/history/sort are fully
  independent per tab. The sidebar stays shared window chrome across tabs.
- `TabBarView`: click a tab to switch, "+" or ⌘T for a new tab (opens to
  home), the × on a tab or ⌘W to close it. (Updated post-v1: ⌘W on the last
  tab now closes the window itself, matching standard macOS "close tab, then
  close window" — see the Post-v1 section below.)
- Cmd-double-click a folder in the file list, or "Open in New Tab" from the
  sidebar's right-click menu, opens it in a new tab instead of navigating
  the current one.
- `WindowViewModelTests` covers tab open/close/activate/reactivate-neighbor
  behavior and confirms tabs' history stacks are fully independent.
- `NetworkShareService`: mounts `smb://`/`afp://`/`nfs://` shares via the
  NetFS framework (`NetFSMountURLSync`, wrapped as a clean async function —
  exactly what Finder's ⌘K uses). System auth UI appears automatically if
  supplied credentials are missing or wrong. Credentials are optionally
  saved to the Keychain and auto-filled next time you connect to that host.
- Mounted shares need no extra plumbing to appear in the sidebar — they
  land under `/Volumes` and flow through the same `NSWorkspace`
  mount-notification path `VolumeService` already watches for USB drives.
- **"Connect to Server…"** button at the bottom of the sidebar opens the
  dialog; on success the active tab navigates straight to the new share.
  Typing an `smb://`/`afp://`/`nfs://` address directly into the address
  bar now also mounts it (using saved credentials if any), instead of the
  Phase 3 placeholder "not supported yet" message.
- `FileSystemService` gained Copy, Move (used for Cut+Paste), Rename, New
  Folder, and Move to Trash, all off the main thread. Copy/Move detect name
  collisions and ask the caller how to resolve them (Replace / Keep Both /
  Skip) via an async callback — "Keep Both" appends " (2)", " (3)", …,
  Windows-Explorer-style, matching this app's design language.
- Real Copy/Cut/Paste via `NSPasteboard.general` (works across tabs and
  windows, like the system clipboard should) — Cut marks the pasteboard so
  the next Paste moves instead of copies, and is consumed after one paste.
- The file list's right-click menu now has the full set from SPEC §4.2:
  Open, Open With… (built from `NSWorkspace.urlsForApplications(toOpen:)`),
  Quick Look, Cut/Copy/Paste, Rename, Move to Trash, Get Info, Copy Path,
  New Folder — background clicks (empty space) get a trimmed Paste/New
  Folder menu instead. The sidebar's context menu also gained Copy Path.
- Keyboard: Return opens the selection, Delete/⌫ moves it to the Trash,
  Space toggles Quick Look, and Cmd+C/X/V work as expected — all wired via
  a small `NSTableView` subclass overriding `doCommand(by:)` and the
  standard edit-menu responder methods, not raw key-code sniffing.
  Also added ⇧⌘N for New Folder.
- Quick Look integrates the real `QLPreviewPanel` (spacebar to toggle),
  following Apple's responder-chain pattern rather than a custom preview UI.
- `FileWatcher` wraps FSEvents (debounced 300ms) and Combine-publishes
  external changes to the currently displayed folder; `FileListViewModel`
  refreshes automatically without disturbing history or scroll position.
- **Refresh** (⌘R, View ▸ Refresh, or the ↻ button after Up) is the
  manual fallback for changes FSEvents doesn't report — notably network
  shares changed from another machine. `Tab.refresh()` re-reads both panes;
  `FolderHierarchyViewModel.requestRefreshAll()` has the tree re-read its
  roots and every expanded folder (keeping expansion), and forget the
  children of collapsed ones so they're read fresh when reopened.
- Rename and conflict resolution (Replace/Keep Both/Skip) are simple
  SwiftUI alerts rather than Finder-style inline cell editing — a
  deliberate scope trim to avoid the added risk of getting `NSTableView`
  inline editing subtly wrong without being able to interactively test it.
- 15 new tests (`FileSystemServiceTests` additions, `FileListViewModelTests`
  additions, `FileWatcherTests`) cover new-folder auto-numbering, rename
  collisions, trash, copy/move conflict resolution (all three outcomes),
  and confirm the FSEvents watcher actually fires on a real filesystem
  change and stops cleanly.

- `FullDiskAccessChecker` (Services) detects whether the app currently holds
  the Full Disk Access TCC permission by probing whether `TCC.db` itself is
  readable — there's no public API for this, so this is the same trick most
  apps that need to know use. `RootView` gates `MainWindowView` behind it: if
  access isn't granted, `FullDiskAccessView` explains why OneRoot needs it and
  offers a button that deep-links straight to Privacy & Security → Full Disk
  Access, plus a "Continue Without It" override for the current launch.
  Rechecks automatically when the app becomes active (e.g. coming back from
  System Settings), so it doesn't nag once access is actually granted.
- Keyboard shortcut pass: added Back (⌘[), Forward (⌘]), and Up (⌘↑) to match
  Finder's own bindings, alongside the ⌘T/⌘W/⇧⌘N/Return/Delete/Space/Cmd+C/X/V
  shortcuts already wired in earlier phases.
- `FullDiskAccessCheckerTests` covers the granted/missing/permission-denied
  cases against a fake probe path (not real TCC state).

### Post-v1

- **Search field** (SPEC.md §4.4): the toolbar's search box now actually
  filters the current folder's file list by name (case-insensitive substring
  match), instead of being a placeholder icon. Non-recursive in v1 —
  subfolders aren't searched, matching the spec. Clears automatically on
  navigation, since a filter from the last folder silently carrying over to
  the next would be confusing. `FileListViewModel.searchText` drives it;
  `FileListViewModelTests` covers filtering, clearing, and the
  clear-on-navigate behavior.
- Removed macOS's free "New Window" (⌘N) command and disabled
  `NSWindow.allowsAutomaticWindowTabbing` — v1 is single-window by design
  (only OneRoot's own ⌘T tab bar), but ⌘N was spawning disconnected extra
  windows that macOS then merged into its own native tab strip on top of
  ours.
- **Tree is folders only.** `SidebarViewModel.children(of:)` now filters out
  files — the tree is for navigation, not browsing; files still show up
  normally in the file list once you select a folder.
- **⌘W closes the tab, then the window.** Closing the last tab now leaves
  `WindowViewModel.tabs` empty instead of auto-opening a fresh one;
  `MainWindowView` detects the empty state and closes the actual `NSWindow`
  (via a small `WindowAccessor` helper), matching standard macOS "close tab,
  then close window" behavior.
- **Expanded tree context menu**: right-clicking a folder in the sidebar now
  has the full set from the file list — Cut/Copy/Paste, Rename, Move to
  Trash, Get Info, Copy Path, New Folder — plus Pin/Unpin and "Show in File
  List". Root-level items (volumes, pinned entries, cloud locations, Trash)
  hide the operations that don't make sense on a mount point (Cut/Copy/
  Rename/Trash/Pin), keeping Open in New Tab/Eject/Paste/Get Info/Copy
  Path/New Folder. `SidebarViewModel` gained the same Cut/Copy/Paste/
  conflict-resolution machinery `FileListViewModel` already had (now backed
  by a shared `ClipboardOperation` pasteboard type so cutting from the tree
  and pasting in the file list, or vice versa, just works); operations
  invalidate and re-fetch only the affected tree node via a new
  `refreshRequest`/`refreshChildren(of:)` path instead of reloading the
  whole tree.
- **Pin folders to the sidebar**, in a real **Pinned** section with a
  Finder-style floating group header and separator — it only appears once
  something is actually pinned. `PinnedLocationsService` persists pinned
  folder paths (plain `UserDefaults` — not sandboxed, so no security-scoped
  bookmarks needed); trashing a pinned folder auto-unpins it rather than
  leaving a broken row behind.
- Four sidebar sections total, always in this order (per two rounds of
  feedback settling on this exact layout): **Pinned** (only once something's
  pinned) → **Mounted** (USB drives, network shares, and mounted DMGs —
  everything `VolumeService` enumerates *except* the boot disk) →
  **Locations** (the boot disk itself, `/Applications`, the current user's
  home folder, and cloud-storage mounts) → **Special** (just Trash, a fixed
  root at `~/.Trash`). This deliberately diverges from real Finder's exact
  sidebar grouping.
- Sections are real `NSOutlineView` group rows (`outlineView(_:isGroupItem:)`
  + `floatsGroupRows = true`), not just visual grouping — `SidebarViewModel`
  exposes `sections: [SidebarSection]` (stable `id` per section so the
  outline view can tell "a section was born/died" apart from "its contents
  changed") and `FolderOutlineViewController` owns a persistent
  `SidebarSectionHeader` per title so expansion state survives rebuilds,
  the same identity-preserving pattern already used for volume `FileNode`s.
- **Fixed a bug** where pinning a folder made it a top-level root, and the
  "hide Cut/Copy/Rename/Trash/Pin on root items" rule (root items being
  mount points you shouldn't casually rename/trash) then also hid the
  "Remove from Sidebar" option on that same pinned item — pinning something
  made it permanently un-unpinnable via the menu. Fixed by keying off the
  node's `kind` ("Pinned" vs "Volume"/"Cloud Storage"/"Trash") instead of
  just "is this a root," so a pinned folder keeps behaving like the regular
  folder it is (cuttable, renameable, unpinnable) while actual mount points
  still hide those operations.
- **Cloud-storage mounts (Nextcloud, Google Drive, Dropbox, etc.) now show
  up.** These never appeared before because apps like Nextcloud's desktop
  client don't mount as classic volumes on modern macOS — they register a
  File Provider extension instead, which `FileManager.mountedVolumeURLs`
  can't see at all (confirmed via `ps aux` showing Nextcloud's
  `FileProviderExt.appex` running, with its data actually living under
  `~/Library/CloudStorage/`). Finder handles this by special-casing that
  folder in its own sidebar; `CloudStorageLocationsService` does the same
  thing, so any provider using this mechanism shows up automatically, not
  just Nextcloud.
- New tests: `PinnedLocationsServiceTests`, `CloudStorageLocationsServiceTests`,
  and `SidebarViewModelTests` additions covering the directories-only filter,
  pin/unpin + persistence, Trash/cloud-storage root placement, and
  trash-auto-unpins-a-pinned-folder.

### Drag and drop

- Both the file list and the sidebar tree are now full `NSDraggingSource`/
  `NSDraggingDestination` implementations, dragging real file `NSURL`s (not
  `NSFilePromiseProvider` — the files already exist on disk, no promised
  content to generate). Because dragging goes through the system pasteboard
  rather than app-internal state, this interoperates with Finder and other
  apps, and with any other OneRoot window, for free — nothing window- or
  tab-specific was needed on the destination side.
- Default drop = **copy**; holding ⌘ during the drop = **move**. This is a
  deliberate simplification of Finder's own convention (which defaults to
  move within a volume, copy across volumes, and reverses the ⌥/⌘ meaning
  depending on that) — copy-by-default is the safer choice given I can't
  interactively test modifier-key behavior myself, and it avoids silently
  moving files somewhere the user didn't intend on a stray drag.
- Dropping onto a folder row/node moves or copies into that folder;
  dropping onto the file list's background drops into whatever directory
  the tab is currently showing. The sidebar tree only accepts drops on an
  actual folder node — there's no sensible target for a drop on empty tree
  space.
- Dropping a folder into itself or one of its own descendants is rejected
  outright (`isValidDropTarget` in the new `Views/DragAndDrop.swift`, shared
  by both destinations). Dropping something back into the folder it's
  already in is a silent no-op for a move, but still makes a numbered
  duplicate for a copy — matching how Option-dragging a file onto its own
  folder works in Finder.
- **Cross-tab dragging**: only the active tab's file list is ever mounted
  (SwiftUI doesn't render inactive tabs at all), so there's nothing to drop
  onto in a background tab. `TabBarView` now switches tabs when a drag
  hovers over a tab button for ~0.6s, Safari-style, so the tab's file list
  mounts and becomes a real drop target before you release.
- New tests (`FileListViewModelTests`, `SidebarViewModelTests`) cover the
  actual file-system side of a drop — move, copy, the same-folder no-op,
  and the current-directory refresh — since the drag *gesture* itself, and
  all ⌘/⌥-modifier behavior, can only be verified by hand.

### Sidebar live updates

- The tree now watches for changes made outside the tree itself — in
  Finder, Terminal, another app, or this app's own file list in a different
  tab — and refreshes the affected folder automatically, the same live-
  refresh `FileWatcher` already gave the file list in Phase 7.
- `FileWatcher.watch(_:)` now takes an array of URLs (FSEvents natively
  supports watching several paths in one stream) instead of one, and a new
  `drainChangedPaths()` exposes exactly which paths changed — needed here
  because Combine's `debounce` only forwards the *last* signal in a burst,
  and the sidebar needs to know about every folder that changed during
  that burst, not just one.
- `SidebarViewModel` watches every current top-level root (Pinned, Mounted,
  Locations, Special) — not each individually-expanded node — since FSEvents
  has no non-recursive mode: watching a root also reports everything below
  it for free. Each reported change becomes a `refreshRequests` entry for
  its parent folder, which `SidebarView` drains into the same
  `refreshChildren(of:)` path already used for the tree's own operations.
  `refreshRequests` had to become a `Set<URL>` (was a single `URL?`) since
  one burst can now legitimately affect several unrelated folders at once.
- Fixed a real (if previously latent) bug surfaced by this work: FSEvents
  reports paths through resolved symlinks (`/private/var/...`), while
  `FileManager.temporaryDirectory` and some volume/mount paths use the
  unresolved form (`/var/...`) — `standardizedFileURL` doesn't reconcile
  this, so `reveal(url:)`'s tree-selection sync could already silently fail
  to match for any path touching a symlink. Both `reveal(url:)` and
  `refreshChildren(of:)` now compare `resolvingSymlinksInPath()` forms
  instead.

### ⌘N restored, and a test-suite fix

- **⌘N opens a new window again.** Removing it earlier also fixed the
  native-tab-bar bug (see the "Fixed pinning + expanded sidebar context
  menu" phase above), but threw out multi-window support entirely, which
  wasn't the actual ask — the fix was specifically `NSWindow.
  allowsAutomaticWindowTabbing = false`, not removing ⌘N. Restored the
  default "New Window" command; `allowsAutomaticWindowTabbing` stays off,
  so windows still never merge into that native strip.
- **Fixed real flakiness in the sidebar-watcher tests**, found while
  verifying the above. `SidebarViewModel` always creates and starts a real
  `FileWatcher` in `rebuildSections()` — including watching the actual
  `/Applications` and the real home directory, unconditionally, even in
  tests. A test using a genuine `FileWatcher` was racing against real
  background filesystem activity on whatever machine ran it (Xcode,
  Spotlight, cloud sync, etc.), not just its own deliberate write.
  `FileWatcher`/`FileListViewModel`/`SidebarViewModel`/`WindowViewModel` all
  gained a `FileWatching` protocol point, defaulting to a new
  `NullFileWatcher` (does nothing) so tests stay hermetic by default;
  `MainWindowView` injects real `FileWatcher`s explicitly. The one test that
  needs to verify the translation logic itself now uses a synthetic
  `FakeFileWatcher` it can fire on demand — deterministic, no real FSEvents,
  no timing dependency — rather than re-testing FSEvents plumbing that
  `FileWatcherTests` already covers.
- Also fixed a related bug surfaced along the way: `handleExternalChange`
  was calling `refreshRequests.insert(_:)` once per changed path in a loop,
  where a single filesystem change can report more than one path at once
  (e.g. a new file plus its parent directory's own mtime bump) — each
  `insert` is a separate `@Published` mutation, so one burst could publish
  multiple times instead of once. Now batched into a single `formUnion`.

### iCloud Drive

- **Fixed a gap in "Locations": iCloud Drive was missing.**
  `CloudStorageLocationsService` only scanned `~/Library/CloudStorage/` —
  where Nextcloud, Google Drive, Dropbox, etc. register their File Provider
  mounts — but iCloud Drive predates that convention and lives at its own
  legacy path, `~/Library/Mobile Documents/com~apple~CloudDocs`, so it was
  never found. (`~/Library/Mobile Documents/` itself is full of ~100+
  other per-app iCloud containers — Notes, Pages, WhatsApp, etc. — none of
  which belong in the sidebar; only `com~apple~CloudDocs`, the general
  Files-app iCloud Drive folder, does.) The service now also
  existence-checks that specific path (not everyone has iCloud Drive
  enabled) and includes it if present.
- Its raw folder name (`com~apple~CloudDocs`) isn't something to show a
  user, unlike third-party mounts whose folder names are already
  presentable (e.g. "Nextcloud-account") — `SidebarViewModel` special-cases
  it to display "iCloud Drive".
- New tests cover both the "present" and "not present" cases for iCloud
  Drive detection, and the display-name special-case; existing
  `CloudStorageLocationsServiceTests` needed to explicitly point
  `iCloudDriveURL` at a nonexistent path to stay hermetic, since this dev
  machine actually has iCloud Drive enabled.

### Trash (Restore/Delete Immediately/Empty Trash), tree navigation, and terminal integration

- **Trash-aware file list.** Right-clicking (or pressing ⌫) inside `~/.Trash`
  now shows **Restore**/**Delete Immediately** instead of "Move to Trash" —
  `FileTableController.isViewingTrash` (set by `FileListView` comparing the
  current directory to the Trash path) swaps the menu and the ⌫ action.
  "Delete Immediately" always confirms first (`hasDestructiveAction`
  button), matching Finder.
- **Restore is honest about its real limitation.** I checked — macOS stores
  no original-location metadata anywhere a third-party app can read
  (verified via `xattr`/`mdls` on a real trashed file); Finder's own "Put
  Back" is private, Finder-only bookkeeping. New `TrashOriginService`
  records the original path whenever OneRoot itself moves something to
  Trash (persisted via `UserDefaults`, so it survives a relaunch) — Restore
  uses that when available, and falls back to an `NSOpenPanel` prompt for a
  destination otherwise (per your call on the tradeoff). `FileSystemService.
  moveToTrash` now returns where each item actually landed (names can get
  de-duplicated) so the origin can be recorded against the right path;
  gained `restoreFromTrash`/`deletePermanently` alongside it.
- **Volumes with no Trash.** Some volumes (NFS/SMB shares, mostly) have
  no Trash, so `trashItem` fails with `NSFeatureUnsupportedError`. After a
  Move to Trash, `TrashFallback` gathers those items and asks once —
  "can't be moved to the Trash. Delete immediately?", destructive button,
  "can't be undone" — then deletes them for good and records that in File
  Operations as its own "Deleting … immediately" entry. Cancel leaves them
  in place as failures of the trash (Retry asks again) without an extra
  error alert. Not undoable.
- **When the open folder disappears** (trashed from the tree or another
  app, or its drive or share goes away), the tab moves to the nearest
  folder above it that still exists, so a Workspace or split pane stays
  where it was. Only when nothing is left above it but `/` or `/Volumes`
  does it go home (`FileSystemService.nearestExistingFolder(above:)`).
- **Empty Trash** on the sidebar's Trash node — confirms first, then
  permanently deletes everything inside via the same `deletePermanently`,
  clearing any recorded origins for what it removed.
- **Tree starts collapsed.** Root nodes (Macintosh HD, home, etc.) no longer
  auto-expand their contents on launch — only the section headers
  (Pinned/Mounted/Locations/Special) do, matching Finder. New ⌘−/⌘+
  collapse everything back to headers / re-expand one level.
  `FolderOutlineViewController.expandTopLevel()` deliberately isn't a
  recursive expand-everything — this tree is rooted at the filesystem, so
  recursively expanding a volume root would mean lazily loading and
  expanding every folder on the entire disk.
- **⌘O opens, Return renames** — swapped to match Finder's actual
  convention (Return used to open; ⌘O is the new "same action, different
  key" for that). `FileTableView.keyDown` now routes Return to rename and
  ⌘O to what Return used to trigger.
- **Open in Terminal** on folders in both the tree and the file list (for a
  selected file, opens at its enclosing folder), via `NSAppleScript`
  telling Terminal.app to `cd` into the path — there's no document-open API
  for "start a shell here." Triggers a one-time Automation permission
  prompt (`NSAppleEventsUsageDescription`, added to Info.plist).
- **Fixed ⌘− collapsing the wrong thing.** It was collapsing the section
  headers themselves (hiding Pinned/Mounted/Locations/Special entirely),
  not just each root's contents — `collapseAll()` now only collapses each
  root node; the headers always stay expanded, since they're labels, not
  something to hide.

### New Folder name prompt, and two new "New Folder" variants

- **New Folder now prompts for a name** (in both the file list and the
  sidebar tree) instead of always creating "New Folder" and leaving you to
  rename it after — matching how you'd expect it to work, still
  auto-numbering on a collision if the name you type is already taken.
- **New Folder and Open** (⌘⌥N, or from the context menu) — same as New
  Folder, but navigates into it immediately after creating it.
- **New Folder Here**, right-clicking a specific folder in the file list —
  creates the new folder inside *that* folder regardless of what directory
  the list is currently showing, then navigates into it. (The sidebar
  tree's existing "New Folder" already creates inside the right-clicked
  node; this adds the same "and navigate into it" behavior to the file
  list, targeted at a specific row rather than the current directory.)
- All three funnel through one `FileListViewModel.pendingNewFolderIntent`
  (an enum: create in the current directory, optionally opening it, or
  create inside a specific node) rather than three parallel prompt flags —
  one alert in `FileListView`, one `createFolder(named:)` that switches on
  whichever intent is pending.

### File menu

- All three "New Folder…" actions now also appear in a real **File** menu,
  not just as keyboard shortcuts — `OneRootApp`'s `.commands(CommandGroup
  (after: .newItem))` inserts them after "New Window".
- Getting there needed a `FocusedValues.activeFileListViewModel` key that
  `MainWindowView` publishes via `.focusedSceneValue` — `.commands` blocks
  live outside any window's view hierarchy, so this is how they find out
  which window (and which of its tabs) is actually frontmost in this app's
  multi-window setup. The two hidden `Button`+`.keyboardShortcut` shims
  that previously drove ⇧⌘N/⌘⌥N directly are gone now that the File menu's
  own commands provide those same shortcuts.
- **Fixed a serious bug from the first version of this**: every menu in
  the app's menu bar stopped closing after being opened — not hung, but
  unusable, requiring a force-quit. Cause: "New Folder Here" originally
  reflected the file list's live selection by wrapping the resolved
  `FileListViewModel` in a nested `@ObservedObject` view inside the
  `.commands` content, so it would enable/disable as selection changed.
  That combination — a Combine subscription driving SwiftUI re-renders of
  *menu bar content specifically* — doesn't play well with `NSMenu`'s own
  tracking run loop while a menu is open. `FileListViewModel` still
  gained `selectedNodes` (mirrored from `FileTableController`'s
  `NSTableView` selection via a new `onSelectionChange` callback, deferred
  to the next run loop turn to avoid the *other* "publishing from within
  view updates" issue below) since it's independently useful, but the File
  menu itself now reads `@FocusedValue` as a plain snapshot with no
  subscription layered on top — the same minimal pattern Apple's own
  Commands sample code uses. "New Folder Here" trades away live
  enable/disable-on-selection-change for this stability: it's disabled
  only when no window is focused at all, and silently no-ops if invoked
  without a valid single-folder selection.
- **Also fixed a related, separate bug**: opening any menu could hang the
  app outright (SwiftUI's "Publishing changes from within view updates is
  not allowed" fault). Setting `FileTableController.items` inside
  `updateNSView` calls `reloadData()` then `selectRowIndexes()` to restore
  selection — both fire `tableViewSelectionDidChange` *synchronously*, and
  the new `onSelectionChange` callback was publishing straight into
  `selectedNodes` from inside that same view-update pass. Deferred via
  `DispatchQueue.main.async`, matching the pattern already used elsewhere
  in this codebase (`revealRequest`, `refreshRequests`) for the identical
  reason.

### Customizable file list columns

- Right-click any column header to show/hide columns via a checklist.
  Name is the anchor column and can't be removed; everything else — Date
  Modified, Date Created, Date Added, Date Last Opened, Size, Kind, Tags,
  Extension — is optional and sortable like the original four. New
  `FileColumn` (`Models/`) replaces the old `SortField` enum and is the
  single source of truth for title/default width/sortability.
  `FileSystemService`'s resource-key prefetch grew accordingly
  (`.creationDateKey`, `.addedToDirectoryDateKey`, `.contentAccessDateKey`,
  `.tagNamesKey`) so populating the new columns costs no extra `stat`
  calls.
- Column visibility is one app-wide preference, not per-tab (unlike sort,
  which stays per-tab on purpose — see `Tab`): a new `ColumnPreferencesStore`
  singleton (`ViewModels/`) persists the visible set via
  `ColumnPreferencesService` (`UserDefaults`, same pattern as
  `PinnedLocationsService`) and every open tab/window's
  `FileListViewModel` observes it via Combine, so toggling a column
  anywhere updates the file list everywhere immediately.
- The header's right-click menu uses the same manual `popUp` workaround as
  the existing row context menu (`FileTableHeaderView`, mirroring
  `FileTableView`) — this dev environment's automatic `NSView.menu`
  right-click path doesn't reliably show anything for these table/outline
  views.
- **Drag to reorder columns.** `allowsColumnReordering` is on; Name stays
  pinned as the leftmost column (`tableView(_:shouldReorderColumn:toColumn:)`
  blocks moving it or dropping anything ahead of it). Dragging posts
  `NSTableView.columnDidMoveNotification`, which `FileTableController`
  reads the table's new column order from and persists via
  `ColumnPreferencesStore.setOrder(_:)` — same app-wide, live-synced-
  across-tabs preference as visibility. `FileColumn.normalized(_:)`
  replaced the old `canonicalOrder(_:)`: loading/toggling no longer force
  columns back into `allCases` order, since that would silently discard a
  user's drag every time they showed/hid an unrelated column.
- **Column widths.** `columnAutoresizingStyle` is `.noColumnAutoresizing`:
  widening a column pushes the rest right and the list scrolls sideways
  once they don't fit, as in Finder. (AppKit's default, last-column-only,
  took the width from the last column until it hit its minimum, after
  which no column could be resized.) Name fills spare width when the
  view is wider than the columns and shrinks back to the width the user
  gave it when the view narrows (`fitNameColumn()`). Widths last for the
  table's lifetime; they aren't saved.
- New `ColumnPreferencesServiceTests`; `FileSystemServiceTests` extended
  to cover the new metadata fields.

### New File

- Right-click (row or background) → **New File**, or ⌘F, prompts for a
  name and creates an empty file in the current directory —
  `FileSystemService.createFile(named:in:)` mirrors `createFolder`
  exactly, including "New File (2)" auto-numbering on a name collision.
  No "New File Here"/"and Open" variants, unlike folders — files don't
  have "open into" semantics, and it wasn't asked for.
- Note: ⌘F is Find in most Mac apps, but there's no existing use of it in
  OneRoot (the search field has no shortcut of its own), and this was an
  explicit choice, not a default — worth remembering if a real Find
  feature ever gets added later.
- Threaded through the same way as "New Folder": `FileListViewModel.
  pendingNewFileIntent` (a plain `Bool` this time — no per-intent data
  needed) drives a `FileListView` alert; `FileTableController.onNewFile`
  carries the context-menu trigger; the ⌘F shortcut is another hidden
  `Button`+`.keyboardShortcut` in `MainWindowView`, matching ⇧⌘N/⌘⌥N (the
  README's older "File menu"/`CommandGroup`/`FocusedValue` section above
  describes a mechanism that no longer exists in the code — apparently
  reverted at some point without the doc being updated; the hidden-Button
  shim you see in `MainWindowView` today is the real, current mechanism).
- New `testCreateFileUsesRequestedNameAndIsEmpty` /
  `testCreateFileAutoNumbersOnCollision` in `FileSystemServiceTests`.

### Custom sidebar tree icons

- Every row in the sidebar tree now uses bundled custom artwork instead of
  the real macOS file icon (`NSWorkspace.shared.icon(forFile:)`, gone from
  `FolderOutlineView`). Eight new image sets in `Assets.xcassets`
  (`boot-volume`, `usb`, `network`, `pinned`, `applications`, `cloud`,
  `trash-bin`, `folder`) generated at 16pt/32pt from source PNGs the same
  way `AppIcon` was (`sips -Z`, preserving aspect ratio for the one
  non-square source). `folder` is the fallback for every ordinary
  subfolder anywhere in the tree, not just the roots.
- `FolderOutlineView.icon(for:)` picks the asset by the node's `kind` tag
  (set in `SidebarViewModel.rebuildSections()`) — `SidebarViewModel` now
  tags the boot volume distinctly from other mounted volumes ("Boot
  Volume" vs "Volume"), Applications distinctly from Home (both used to
  share "Folder"), and mounted volumes get "Network Volume" instead of
  "Volume" when `VolumeInfo.isLocal` is false. `VolumeService` populates
  `isLocal` from `URLResourceKey.volumeIsLocalKey` — the correct signal
  for "is this actually a network share," as opposed to guessing from
  `isRemovable`/`isEjectable` (a mounted disk image is ejectable but
  local, and would've been misclassified as network under that
  heuristic).
- **Home shows the macOS account picture**, matching what real Finder
  does for its own Home entry. New `AccountPictureService` reads it via
  the OpenDirectory framework (`kODAttributeTypeJPEGPhoto` on the current
  user's record) — system framework only, no third-party dependency,
  returns raw `Data` rather than `NSImage` to stay Foundation-only per
  CLAUDE.md §1 (image construction happens in `FolderOutlineView`, the
  view layer, same as everywhere else icons are built). Falls back to the
  generic `folder` icon if the account has no custom photo. Fetched once
  and cached (`lazy var accountImage`) rather than re-querying
  OpenDirectory on every row redraw.
- `imageScaling` explicitly set to `.scaleProportionallyDown` on the
  tree's `NSImageView` — matters now that one source image
  (`boot-volume`) isn't perfectly square; previously every icon came from
  `NSWorkspace` and was always square, so this never came up.
- **File list folders match too.** `FileTableController`'s Name column
  used the real macOS folder icon even after the tree switched to custom
  artwork, which looked disconnected — folders there now use the same
  `folder` asset; files (no per-type custom art exists yet) keep their
  real `NSWorkspace` icon.

### Sidebar fix: right-click no longer navigates the active tab

- Right-clicking a different tree row to get its context menu was also
  silently navigating whatever tab you were looking at to that row —
  `ContextMenuOutlineView.rightMouseDown` selects the clicked row so the
  menu has something to act on (and so it's visually highlighted, like
  Finder), but that selection change flowed straight into
  `outlineViewSelectionDidChange` → `onSelect` → `navigate(to:)`
  unconditionally, with nothing distinguishing "selected because
  right-clicked" from "selected because the user actually clicked it."
  New `isRightClickSelecting` flag on `ContextMenuOutlineView`, set only
  for the duration of that one `selectRowIndexes` call, lets
  `outlineViewSelectionDidChange` skip calling `onSelect` for it. Right-
  click still highlights the row and shows the menu (so "Open in New
  Tab" etc. act on the right item) — it just no longer changes what the
  current tab is showing.

### Show Hidden Files toggle

- New toolbar button (eye/eye-slash icon, next to the search field) and
  ⌘⇧. — Finder's own shortcut for the same thing — toggle whether
  dot-prefixed files show in the file list. `FileSystemService.
  listDirectory(_:includeHidden:)` now takes the flag and omits
  `.skipsHiddenFiles` from its `FileManager` options when it's on.
- Same app-wide, live-synced-across-tabs pattern as column visibility:
  `HiddenFilesPreferenceStore` (`.shared`) + `HiddenFilesPreferenceService`
  (`UserDefaults`). Unlike column visibility, though, a change here can't
  just re-filter what's already in memory — hidden entries were never
  fetched from disk at all while the preference was off — so
  `FileListViewModel` calls `refresh()` (a real re-fetch) when it changes,
  guarded against the `@Published` publisher's initial replay-on-subscribe
  so opening a new tab doesn't trigger a pointless extra reload before its
  first real `navigate(to:)`.
- New `HiddenFilesPreferenceServiceTests`; `FileSystemServiceTests` gained
  `testHiddenFilesAreIncludedWhenRequested`.

### Configurable terminal app

- OneRoot's first real Preferences surface: a `Settings` scene (⌘,),
  `Views/Settings/SettingsView.swift`. One setting so far — "Terminal
  App" — with a "Choose…" `NSOpenPanel` (any `.app` under
  `/Applications`) and a "Use Default" reset.
- `TerminalPreferenceService` stores the chosen app's *bundle
  identifier*, not a path — survives the app being moved/reinstalled.
  Stays Foundation-only per CLAUDE.md §1: resolving a bundle identifier
  to an actual app URL is an `NSWorkspace` call, so that happens at the
  view/AppKit layer (`OpenInTerminal.swift`), not in the service.
- `openInTerminal(_:)`: unconfigured (default) still goes through the
  original AppleScript `tell application "Terminal"` path, unchanged —
  Terminal doesn't expose a document-open API for "start a shell here,"
  so this is the same mechanism Finder's own "New Terminal at Folder"
  uses. A configured custom app instead goes through `NSWorkspace.open(_:
  withApplicationAt:)` — no AppleScript dictionary needed, no Automation
  permission prompt, and it's how most non-Apple terminals (iTerm2, Warp,
  etc.) register to be launched at a folder. This is "best effort": it
  works if the chosen app treats being opened with a folder as "start a
  session there," which isn't guaranteed for every terminal emulator,
  but is a widely-adopted enough convention to not need per-app special
  cases.
- New `TerminalPreferenceServiceTests`.
- **Follow-up #1**: the "best effort" document-open path above didn't
  work for Tabby (opened the app but not at the right folder, no new
  tab/window) — confirmed several non-native/Electron terminals (Tabby,
  kitty, Alacritty among them) don't implement that convention and need
  an explicit CLI invocation instead. Added a second, opt-in "Open-Folder
  Argument" Settings field — when set, `openInTerminal(_:)` switches to
  `NSWorkspace.openApplication(at:configuration:)` with `[argument,
  url.path]` as launch arguments plus `createsNewApplicationInstance =
  true` (so an already-running instance doesn't just get activated
  without picking up the new folder).
- **Follow-up #2**: the first guess at what to put in that field for
  Tabby (`--working-directory`) was wrong and still didn't work — checked
  Tabby's actual CLI source
  (`Eugeny/tabby`'s `app/lib/cli.ts`) rather than keep guessing. Tabby's
  CLI is yargs-style subcommands, not flags: `tabby open <directory>` —
  so the correct value is the plain word `open`, no dashes. Renamed the
  Settings field/help text from "Working Directory Flag" to "Open-Folder
  Argument" and dropped the `--flag`-shaped placeholder, since the right
  value isn't always a flag (confirmed by this exact case).

### Trash context menu was showing normal file operations

- Right-clicking an item *inside* Trash showed the full normal menu
  (Open, Open With, Quick Look, Cut/Copy/Paste, Rename, Get Info, Copy
  Path, Open in Terminal, New Folder…) with Restore/Delete Immediately
  just inserted in the middle — all of that beyond Restore/Delete
  Immediately either doesn't apply to something already in the Trash or
  fights with Finder's own Trash semantics.
  `FileTableController.menuNeedsUpdate` now returns immediately with
  just those two items when `isViewingTrash`, before building any of the
  rest. Right-clicking Trash's empty background now shows nothing too
  (previously offered Paste/New Folder, which don't apply there either)
  — same early-return idea, applied to `appendPasteAndNewFolder`'s call
  site instead of inside it.

### Address bar autocomplete

- Something Explorer has and Finder doesn't: a dropdown of matching
  subfolder names as you type in the address bar. ↑/↓ to move through
  it, Return or a click to accept (fills in the folder plus a trailing
  `/` and immediately shows what's inside *that*, so you can keep
  drilling down without pausing), Esc to dismiss.
- Split into a pure, testable half and an I/O half, matching the
  existing service/view boundary: `PathResolver.splitForAutocomplete(_:)`
  (new) parses address-bar text into "which folder to look in" +
  "what prefix to match" — no disk access, just string/URL logic — and
  `FileSystemService.suggestFolders(in:)` (new) does the actual
  `FileManager` listing, off the main thread like everything else here,
  fetching only `.isDirectoryKey` (files can't be navigated into, so
  skipped) instead of the full resource-key set `listDirectory` needs.
- **Performance** (the thing this was designed around, not an
  afterthought): `AddressBarView` caches the last-listed directory's
  full child-name list, so only the *first* keystroke into a new
  directory touches disk — every keystroke after that while still
  inside the same directory just re-filters the cached array in memory,
  which is effectively free. Each lookup also runs in a cancelable
  `Task`, so typing faster than disk I/O returns doesn't let a stale
  result clobber a newer one, and results are capped at 50 matches so
  the dropdown itself stays cheap even in huge folders.
- Caught a real bug via the tests written for this:
  `NSString.expandingTildeInPath` doesn't reliably preserve a trailing
  slash, which broke the "just typed a `/`, show everything in this
  folder" case (`/Users/eric/` was being split as directory `/Users`,
  prefix `eric` instead of directory `/Users/eric`, prefix empty).
  Fixed by checking the trailing slash on the *raw* input before
  expansion, not on the expanded string.
- Deliberately scoped to folders only (matches this address bar's
  navigate-into-a-directory model) and to local/`~` paths — not
  network addresses, since suggesting folder names for a share that
  isn't mounted yet doesn't mean anything.
- New tests: `PathResolverTests`' `splitForAutocomplete` cases,
  `FileSystemServiceTests`' `suggestFolders` cases.
- **Follow-up fixes** after trying it for real:
  - The dropdown wasn't tall enough to show every match, and ↑/↓ could
    move the highlight past what's visible — it moved (Enter on an
    off-screen highlighted item worked) but nothing scrolled to reveal
    it. `suggestionList` now wraps its `ScrollView` in a
    `ScrollViewReader` and calls `scrollTo(_:anchor:.center)` whenever
    `highlightedSuggestionIndex` changes, and the cap grew from 200pt to
    280pt. Also dropped a `.fixedSize(vertical: true)` that was fighting
    the height cap — telling a `ScrollView` to take its "ideal" size
    defeats clipping/scrolling within a `maxHeight`.
  - Clearing the address bar and retyping without a leading `/` or `~`
    (e.g. just typing a bare folder name while still viewing some
    folder) produced no suggestions at all — `PathResolver.
    splitForAutocomplete` only recognizes absolute-looking input by
    design (pure/context-free, no notion of "current directory"). New
    `AddressBarView.autocompleteSplit(for:)` wraps it with a fallback:
    non-empty text that isn't absolute-looking is now treated as a
    plain prefix against `viewModel.currentDirectory`, so bare typing
    autocompletes relative to wherever you're currently browsing.
  - Also gated the whole autocomplete pipeline behind `isFocused` — it
    was reacting to *programmatic* text changes too (`.onAppear`,
    syncing to `viewModel.currentDirectory`), not just real typing,
    which was quietly leaving stale suggestion/cache state around
    between visits to the field.

### Advanced Search (Phase 9, post-v1)

- A separate window (⌘⌥/, or the magnifying-glass-circle toolbar button)
  for recursive search over a chosen folder or an entire volume — distinct
  from the toolbar's `SearchFieldView`, which only filters names in the
  *current* folder's list, non-recursively. Its own window rather than a
  sheet on purpose: a long search over a whole drive shouldn't block
  browsing in the main window, and more than one search can be open at once.
- Two modes via a segmented control: **Name & Metadata** (Contains/Starts
  With/Ends With/Regex on the name, case-sensitive toggle, plus
  extension/size-range/date-modified-range/include-hidden filters) and
  **File Contents** (grep-style, Contains/Regex against each line of
  candidate files, still narrowed by the same extension/size/date filters).
  Content mode automatically skips non-text files (checked via
  `UTType.conforms(to: .text)`) and anything over 20 MB, counting — not
  silently dropping — what it skipped, so a whole-volume content search
  doesn't stall on a random video file or database.
- `SearchService` (new, UI-agnostic like the other services) walks the tree
  with `FileManager.enumerator` and streams `SearchEvent`s
  (`.matched`/`.progress`) through an `AsyncThrowingStream` as it goes,
  rather than collecting everything before returning — results and live
  "N folders, N files scanned" counts in the status footer update
  incrementally, and Cancel (backed by `Task` cancellation flowing through
  the stream's `onTermination`) actually stops promptly instead of waiting
  for a full walk to finish.
- Results render in a plain SwiftUI `Table` (not the main list's
  `NSTableView` — this one doesn't need drag-and-drop, inline rename, or
  persisted column state, so the lighter option was the right call here).
  Right-click/double-click a result for Open, Reveal in Finder, Copy Path,
  and **Open in OneRoot**, which posts a `.revealInOneRoot` notification
  that every open main window observes — `MainWindowFocusTracker` records
  which main window was most recently key so only *that* one navigates,
  instead of every open window jumping at once.
- One deployment-target gotcha: `TableColumnBuilder`'s `if`/`else` needs
  macOS 14.4, but this app's target is 14.0, so the Name/Metadata and
  Contents layouts are two separate `Table`s picked with a plain
  `ViewBuilder` `if`/`else` around them instead of one `Table` with a
  conditional column inside it.
- New `SearchServiceTests` covers name matching (contains/starts/ends/regex,
  case sensitivity), extension/size/hidden-file filters, recursion into
  subfolders, content-mode line matching (including multiple matches per
  file) and binary-file skipping, and the invalid-regex/missing-root error
  paths.

**Follow-up fixes** after trying it for real:
- **Folders weren't matching at all.** `SearchService` had a `guard
  !node.isDirectory` ahead of the name-matching branch, meant only to keep
  content-mode grepping away from directories, but it was gating *both*
  modes — searching "Desktop" from your home folder returned nothing
  because the Desktop folder itself was filtered out before name matching
  ever ran. Moved the file-only restriction into the `.contents` case only;
  `.nameAndMetadata` now matches folders same as files (their `size` is
  `nil`, so a size filter still naturally excludes them if one's set,
  without special-casing). New tests: `testNameSearchMatchesFolders`,
  `testContentSearchDoesNotMatchFolderNames`.
- **File chooser, redesigned** (supersedes the description below): laid
  out like the main window in a resizable sheet — Back/Forward/Up and an
  editable path field (type or paste a path and press Return; `~` works;
  matching subfolders are suggested as you type, Tab takes the first; a
  missing path is flagged without moving; a pasted file path opens its
  folder with the file selected when files can be chosen), then three
  columns: places (Home, Pinned, Cloud, Locations), a folder tree rooted
  at the place holding the current folder and opened down to it, and the
  folder's contents (Name, Date Modified, Kind; double-click or Return
  opens a folder or chooses an item). A **Show Hidden Files** checkbox
  starts from the main window's setting. Multiple selection (⌘/⇧-click)
  is only on for Workspace ▸ Add (`init(multipleFoldersStartingAt:)`);
  every other caller still picks one item. The logic is the tested
  `FileChooserViewModel`. No keyboard shortcuts for Back/Up/hidden inside
  the sheet: the main menu's ⌘[, ⌘↑, and ⇧⌘. would act on the window
  behind it instead.
- **Replaced every remaining `NSOpenPanel` in the app** with a new
  `FileChooserView` (`Views/Dialogs/`) — a small OneRoot-styled sheet (a
  volumes column + a file/folder list, up-button, click a row to target it,
  click its chevron to descend into a folder) instead of popping open
  Finder's own picker from inside a Finder-replacement. Deliberately plain
  SwiftUI `List`s rather than the sidebar's `NSOutlineView` tree — this is a
  one-shot "pick something and close" dialog, and the sidebar tree is
  tightly coupled to `SidebarViewModel`'s pinning/trash/rename/drag-and-drop
  machinery, none of which applies here.
  - Generalized beyond Advanced Search's folder-only root picker (its first
    use) to cover the other three `NSOpenPanel` call sites in the app:
    the Trash restore-destination prompt, the Settings Terminal-app picker,
    and the SSH private-key browser — via `canChooseFiles`/
    `canChooseDirectories`/`allowedContentTypes`/`showsHiddenFiles`
    parameters (matching NSOpenPanel's own knobs) plus optional `message`/
    `chooseButtonTitle` text for context-specific prompts ("Restore" instead
    of "Choose", etc).
  - A `.app` bundle (or other package) is a directory on disk but is listed
    and selected as a single item, not browsed into — same rule
    `FileTableController` already uses for Open vs. navigate.
  - The restore-destination prompt used to block synchronously on
    `NSOpenPanel.runModal()` from inside `FileListViewModel`, a plain
    `ObservableObject` with no view of its own. Converted to the same
    "publish a pending-request property + `CheckedContinuation`" pattern
    `resolveConflict`/`pendingConflict` already used for Replace/Keep
    Both/Skip prompts — `FileListView` shows `FileChooserView` in a sheet
    whenever `pendingRestoreDestinationItemName` is non-nil, and
    `resolveRestoreDestination(_:)` resumes the suspended `restore(_:)`
    call either way (a chosen `URL`, or `nil` on cancel).

**Second round of follow-up fixes:**
- **Double-clicking a folder in search results opened it in Finder**
  (`NSWorkspace.shared.open`, the same path used for files). Now a folder
  double-click opens it **in OneRoot, in a new tab** instead — a search
  result is a new place you're going, not the tab you're already in — while
  a file double-click still opens with its default app. The context menu's
  "Open in OneRoot" is unchanged (still navigates the active tab, not a new
  one). Both now route through `RevealInOneRootRequest` (`object` on
  `.revealInOneRoot`), which carries an `openInNewTab` flag so
  `MainWindowView` knows which one to do.
- **`FileChooserView`'s descend-into-folder chevron was barely
  clickable.** Root cause: a `Button` nested inside a `List(selection:)`
  row loses most of its clicks to the row's own selection gesture on
  macOS — a known SwiftUI quirk. Replaced it with a plain `Image` plus
  `.highPriorityGesture(TapGesture())`, which reliably wins that race, and
  gave it more padding so the tap target isn't tiny. Also added
  double-click-to-descend on the row's name/icon area as a second way in,
  as requested.
- **Advanced Search gained a Folders/Files/Files & Folders filter**
  (`SearchCriteria.itemType`, a `SearchItemType` enum), shown as a
  segmented control — only in Name & Metadata mode, since Contents mode is
  inherently files-only already. New tests: `testItemTypeFilterFoldersOnly`,
  `testItemTypeFilterFilesOnly`.
- **Advanced Search's shortcut moved from ⌘⌥F to ⌘⌥/.**

**Third round:**
- **`/` now focuses the toolbar's quick-search field** from anywhere in the
  window, Slack/Gmail-style. Deliberately *not* a global
  `.keyboardShortcut("/", modifiers: [])` — that fires via `performKeyEquivalent`
  ahead of normal text insertion, which would have hijacked the first `/`
  typed into the address bar or Advanced Search on every absolute path.
  Implemented as `.onKeyPress(KeyEquivalent("/"))` on `MainWindowView`
  instead: that bubbles up from whatever's currently focused, so a focused
  text field's own typing consumes the key first and the handler never
  sees it. `FileListViewModel` gained `searchFieldFocusTrigger`
  (bumped by `focusSearchField()`) that `SearchFieldView` observes to move
  `@FocusState` into its `TextField`.
- Help (⌘?) updated for everything from the last two rounds: a new
  "Advanced Search" topic, a `/`-focuses-search note under "The File List",
  and `/` / ⌥⌘/ added to the shortcuts reference.

### Navigation history (Recent Locations)

- **An app-wide browsing history**, separate from Pinned: every folder that
  successfully lists gets recorded, most-recent-first, de-duplicated (a
  re-visit moves the entry to the front rather than adding a second one).
  Surfaced as a **Recent Locations** submenu in the **Go** menu — pick an
  entry to navigate the active tab there — with a **Clear History** item.
- `NavigationHistoryService` persists the list and the cap as plain
  `UserDefaults` (paths + an `Int`; not sandboxed, so no bookmarks).
  `NavigationHistoryStore` is the `@MainActor` `ObservableObject` shared
  across every tab/window (same pattern as `ColumnPreferencesStore` /
  `FileOperationProgressCenter`); `FileListViewModel` feeds it from the
  success branch of its directory load, so a mistyped address-bar path or a
  vanished share never gets recorded, and a live FSEvents refresh of the
  current folder is a no-op (it's already the front entry).
- **Settings → General** gained a "Locations to remember" stepper
  (default 20, clamped to 5–200) and a "Clear Navigation History" button.
  Lowering the cap trims the stored list immediately.
- `WindowViewModel` now takes an injectable `navigationHistory` so its
  tests (and `FileListViewModelTests`) use an isolated store instead of
  writing temp-dir paths into `UserDefaults.standard`. New tests:
  `NavigationHistoryServiceTests` (round-trip, default/clamped limit) and
  `NavigationHistoryStoreTests` (prepend, de-dup, cap, limit-lowering
  trim, clear, cross-instance persistence).
- Help (⌘?) updated: a Recent Locations paragraph under "Navigating" and
  the new controls noted under the General settings bullet.

### Main-menu architecture fix (`WindowMenuState`)

Adding the Recent Locations submenu exposed a latent defect from the
`9dfe4f0` "Add File/Go/View/Help main menu commands" commit: the whole
`.commands` tree — and with it the AppKit menu bar — rebuilt on nearly
every `MainWindowView` render. Menus flickered, closed under the pointer,
and sometimes rendered with items missing. A submenu that tracks the
pointer just made it impossible to ignore.

- **Cause.** `MainWindowView` published five `focusedSceneValue`s, two of
  them freshly allocated closures (`openConnectToServer`,
  `showShortcutsQuickView`). Closures aren't equatable, so every
  `MainWindowView.body` pass changed the focused-value set and forced every
  `Commands` struct to re-evaluate. And `body` re-ran constantly — it owned
  `@State revealRequest` (written on every navigation) and observed
  `sidebarViewModel`, which publishes on every FSEvents tick anywhere under
  a sidebar root. Rebuilding an open `NSMenu` closes / re-lays it out.
- **Fix.** New `WindowMenuState` (`ViewModels/`) — one `@MainActor
  ObservableObject`, created once per window as `@StateObject`, published
  via a single `.focusedSceneObject(_:)`. It hands commands the view models
  by reference for *actions*, and mirrors only the values the menus
  *display* (`canGoBack/Forward/Up`, `selectionCount`, `showHiddenFiles`,
  `selectedSidebarNodeIsEjectable`, `recentLocations`) as `@Published`, each
  guarded with a `!=` check via Combine subscriptions to the active tab's
  `FileListViewModel` and to `SidebarViewModel`. The two former closures are
  now monotonic trigger counters (`connectToServerRequestCount`,
  `shortcutsQuickViewRequestCount`) that `MainWindowView` watches with
  `.onChange` — same pattern as `SidebarViewModel.collapseAllRequestCount`.
  All four `Commands` structs read one `@FocusedObject`.
  `FocusedValues+OneRoot.swift` is now an empty stub.
- **`revealRequest` removed from `MainWindowView`.** Keeping the sidebar
  tree synced to the active tab's directory moved to `WindowMenuState`,
  which feeds a new `SidebarViewModel.revealRequests` `PassthroughSubject`
  (deliberately not `@Published` — it must not trip `objectWillChange`).
  `SidebarView` consumes it with `.onReceive`. Navigation no longer
  re-renders `MainWindowView` at all.
- **Sidebar FSEvents debounce.** `SidebarViewModel` adds a 400 ms coalescing
  stage on top of `FileWatcher`'s own 300 ms debounce, and `rebuildSections`
  now skips re-publishing `sections` when the computed list is unchanged
  (volume re-emits and tree operations mostly produce an identical list).
- **Recent Locations is a real submenu again**, capped at the 12 most
  recent. **Show All History…** opens a new searchable `HistoryView` window
  (`historyWindowID`) with the full stored list (double-click / Open
  navigates the frontmost window's active tab via the existing
  `.revealInOneRoot` notification); **Clear Menu** empties it. Storage cap
  is decoupled from the menu and back to 5–200.
- New `WindowMenuStateTests`: mirrors track the underlying view models
  across navigation and tab switches, trigger counters increment,
  `recentLocations` follows the store.

### Not yet documented above

Features added between the main-menu fix and UX Phase 1, without their own
README sections: clickable breadcrumb path bar, split panes (now Dual Pane),
icon view remembered per folder, preview pane (now the Inspector's
content), Undo/Redo for file operations, byte-level copy/move progress with
Cancel, batch rename, folder sizes, archive Compress/Extract, Copy via SSH,
session restore, themes, and Spotlight/cloud results in Advanced Search.
Corrections to older sections above: Show Hidden Files is in the View menu
(⇧⌘.), not a toolbar eye button. The "copy by default, ⌘ to move" drag
description in "Drag and drop" likely no longer matches: the list and tree
take the drag's own operation mask (move unless ⌥ restricts it to copy),
and the breadcrumbs and destinations are explicitly ⌥ = copy, otherwise
move — not yet re-verified by hand.

### UX Phase 1 — four-region window

The window is reorganized around Destinations → Hierarchy → Contents →
Context (see CLAUDE.md §6), reusing the existing tree and file list:

```
[ destinations | tabs / location / actions               ]
[              | hierarchy | file list | Inspector        ]
[ status bar with tool buttons, opening into the tools panel ]
```

- **Destinations sidebar** (`Views/Destinations/DestinationsSidebarView`,
  SwiftUI, `DestinationsViewModel`): Home; Pinned; Cloud; Locations (boot
  disk, Applications, other volumes and network shares); Special (Trash).
  Shallow — choosing one roots the hierarchy there and takes the active tab
  to it. Context menus per kind (Open in New Tab, Copy Path, Reveal in
  Finder, Open in Terminal, Remove from Sidebar, Eject/Disconnect, Empty
  Trash). Drops move (⌥ copies); a drop on Trash is a real, undoable Move to
  Trash. The highlighted row follows the active tab's root. Home appears
  once; Recents and Starred aren't there (no reliable source yet).
- **Folder hierarchy**: the existing `NSOutlineView`
  (`FolderOutlineViewController`), now rooted at the active tab's
  `HierarchyRoot` instead of every volume at once — no section headers; the
  root row starts expanded. Lazy loading, live FSEvents refresh (now
  watching only the current root), drag and drop, context menus, and
  reveal are unchanged. `SidebarViewModel` became `FolderHierarchyViewModel`
  (tree operations only; volumes/pins moved to `DestinationsViewModel`, pins
  to the shared `PinnedLocationsStore`). Each root's expanded folders are
  remembered and restored when you come back to it.
- **Hierarchy roots** (`HierarchyRootResolver`, `HierarchyCoordinator`):
  each tab keeps its root while you browse inside it; leave it and the tab
  re-roots at the most specific destination containing where you are (else
  `/`). A root that stops being a destination (unpinned, unmounted) is
  re-resolved. Until the first volume list arrives at launch, a root is
  shown but not stored, so a saved root on an external drive isn't lost.
- **Inspector** (`Views/Inspector/InspectorContainerView`): a collapsible
  right pane that hosts the existing preview pane content (Quick Look +
  basic properties) for the focused pane's selection. ⌥⌘I (⇧⌘P still works).
  The old app-wide preview-pane setting seeds the first layout.
- **Tools panel** (`Views/Shell/ContextualWorkspaceView`): the status bar
  gained a **File Operations** button that opens a panel above it (⌃⌘B)
  with the same progress cards as the floating progress windows (which
  still appear). Collapsing never cancels work. Dual Pane was briefly
  moved into this panel and then moved back beside the file list, where it
  always was.
- **Layout** (`WindowLayout`, `WindowLayoutModel`, `Views/Shell/PaneSplitView`):
  destinations, hierarchy, and Inspector live in real
  `NSSplitViewController`s; each is collapsible (View menu: ⌃⌘S, ⌃⌘H, ⌥⌘I)
  and resizable. Visibility and widths are saved per window with the
  session; the last change also seeds new windows. Narrow windows hide the
  Inspector, then the hierarchy, then destinations, without forgetting the
  choice.
- File lists get a fresh `NSTableView` per pane (`.id`), restoring the
  pane's own selection — previously one table was reused across tabs, so
  the selection shown and the one menus acted on could disagree, and a
  pending Quick Look count could fire on tab switch.
- Tests: `DestinationsViewModelTests`, `HierarchyRootResolverTests`,
  `HierarchyCoordinatorTests`, `WindowLayoutTests` (layout, service, model),
  plus additions to `FolderHierarchyViewModelTests`, `WindowViewModelTests`,
  `WindowMenuStateTests`, and `SessionTests` (older sessions still load).

Known limitations: the hierarchy shows one root (Workspaces will add
more); the Inspector is the preview pane, not yet the sectioned Inspector;
the destination sidebar uses SF Symbols rather than the themed artwork the
tree uses.

### UX Phase 2 — visual hierarchy and command styling

- **Three bands**: tabs and the location bar share one surface (the
  active tab is lifted off it); the action bar is ruled above and below.
- **Tabs** (`TabBarView`): 26pt, folder icon (split icon with Dual Pane),
  medium-weight title on the active tab, which sits on the content color
  with a hairline border instead of an accent fill. Close button only on
  the active tab and on hover (⌘W always works). When tabs would shrink
  below 110pt the rest go into a **» n** menu; the active tab always stays
  in the strip. Reordering, tear-off, and drag-hover switching unchanged.
- **Commands** (`BarButtonStyle`, shared): monochrome SF Symbols with a
  soft hover/press highlight and a dimmed disabled state — the burgundy
  two-tone `.circle` glyphs are gone (`ThemeIcons.toolbarPrimary/Secondary`
  are now unused). Color only for state: a pane toggle that's on uses the
  accent; Move to Trash turns red on hover.
- **Location bar**: chevron Back/Forward, Up, breadcrumbs, filter field,
  Advanced Search.
- **Action bar**: New ▾ | Cut, Copy, Paste, Rename, Move to Trash | Sort ▾,
  View ▾, More ▾ (Compress, Extract, Batch Rename, Calculate Size, Copy Path,
  Open in Terminal) … then Destinations / Folder Hierarchy / Inspector
  toggles on the right.
- **File list**: 26pt rows (up from AppKit's default). An overlay
  (`FileListStateOverlay`) says why a list is empty — loading (after
  400ms, so fast folders don't flash a spinner), no permission (with a
  button to Privacy & Security → Full Disk Access), couldn't be read,
  nothing matches the filter (with Clear Filter), or simply empty. Only its
  buttons take clicks, so right-clicking the empty list still gives New
  Folder/Paste. `FileListViewModel` gained `isLoading` (navigations only,
  not passive refreshes), `listingErrorMessage`, and `isPermissionDenied`.
- `FileTableController` now skips `reloadData()` when SwiftUI hands it the
  same listing again (same nodes, same order), so selection or loading
  changes don't reload the table.
- Tests: loading/permission/listing-error states and the same-listing
  check, in `FileListViewModelTests`.
- **Fix:** "Publishing changes from within view updates" in Xcode's console.
  Reloading, expanding, or revealing in the folder hierarchy changed its
  selection, which navigated the tab — sometimes mid SwiftUI update, and
  always as a redundant second load of the folder (clearing its filter).
  Programmatic tree changes no longer count as choosing a folder, and real
  choices (tree and destinations) are acted on a tick later.

### The OneRoot look (mockup pass)

The default look now follows the OneRoot design mockup, using only real
data. The earlier looks remain as options.

- **Themes**: new **OneRoot Light/Dark** (`ThemeCatalog.oneRootLight/Dark`):
  white cards, blue folders, soft blue selection, on macOS's translucent
  sidebar material (`Theme.usesMaterialBackdrop`, `WindowBackdrop`).
  **OneRoot (Automatic)** (stored id `system`) is the default; the old
  automatic look is **macOS (Automatic)** (`system-native`) with the
  burgundy folders, and every community theme stays. Existing installs
  switch to the OneRoot look once (`ThemePreferenceService.
  adoptOneRootDefaultIfNeeded`); choosing another theme afterwards sticks.
- **Window**: no title bar (`.windowStyle(.hiddenTitleBar)`); the
  destination sidebar runs to the top under the window buttons, the tab
  strip sits where the title was (its empty space drags the window,
  double-click zooms). Content is in rounded cards (`.card()`) separated by
  invisible split dividers (`PaneSplitView.transparentDividers`).
- **Sidebar**: custom rows (soft selection pill, accent icons for cloud and
  pinned, eject buttons, arrow keys once focused), and a startup-disk gauge
  with Connect to Server and Settings at the bottom. Drops and context menus
  unchanged.
- **Tabs**: folder-tab shape, the active one joining the card below;
  house icon for the home folder, blue folders otherwise. Search, Advanced
  Search, and the pane toggles (destinations, hierarchy, Inspector, tool
  cards) sit at the right of the strip.
- **File card**: header with Back/Forward/Up, breadcrumbs, New, Sort, a
  Grid/List segmented switch, and **•••** (Cut, Copy, Paste, Rename, Move to
  Trash, Compress, Extract, Calculate Size, Copy Path, Open in Terminal,
  View Options) — the bar no longer has separate Cut/Copy/Paste/Rename/
  Trash icons. Below it the folder hierarchy and list share the card;
  status line at the bottom.
- **List**: 30pt rows, 18pt icons, quieter metadata text, the Kind column
  titled **Type**, default columns Name, Type, Date Modified, Size, Tags,
  and tags drawn as colored chips (`TagChipsCellView`; Finder's standard
  tag colors, gray for custom tags whose color macOS doesn't expose).
- **Inspector** (`InspectorView`, replaces the preview pane): large Quick
  Look preview, icon/name/kind/size, **Open in <default app>** with other
  apps in its menu (a folder opens in place), Share, Copy Path, More
  (Quick Look, Reveal in Finder, Open in Terminal, Rename, Move to Trash),
  Details (dates, size, dimensions/duration, location), tag chips; a
  folder summary when nothing is selected; totals plus Compress/Rename for
  several items. Versions, activity, notes, related files, and AI from the
  mockup are not shown — OneRoot has no real source for them.
- **Tool cards** (`ToolCardsView`): File Operations (live progress and
  Cancel), Dual Pane (on/off switch, each pane's folder, Swap — the panes
  themselves stay side by side in the file card), Quick Actions (New
  Folder, Compress, Batch Rename, Extract, Copy Path, Open in Terminal,
  disabled when they don't apply). Visualize isn't there yet: it needs a
  scanning service first.
- **Layout**: Inspector and tool cards show by default (`WindowLayout`
  version 2 — layouts saved by earlier builds are replaced once with the
  new defaults). **View ▸ Reset Window Layout**. Panes squeezed by a
  narrow window grow back to their size when room returns, and only a
  divider drag (not a window resize) records a new width.

**Follow-up round:**
- **Dual Pane** left the bottom cards; it's a toggle button in the file
  card's command row (and still ⌘\ / View ▸ Dual Pane). The bottom cards are
  File Operations and Quick Actions.
- The file card's header is two rows: Back/Forward/Up and the path, then
  New, Sort, Grid/List, Dual Pane, and ••• (right-aligned).
- The tab strip sits level with the window buttons, in the window's own top
  band (lined up with the sidebar's width), rather than inside the panes.
- **Crash fixed**: an endless AppKit constraint-update loop
  ("…more Update Constraints in Window passes than there are views…"). The
  `NSHostingView` inside each tab (and pane header) fed its content's size
  back out as constraints, which looped with the tab strip's width
  measurement. Those hosting views now have `sizingOptions = []` and
  `safeAreaRegions = []` (the latter so the hidden title bar doesn't push a
  tab's content down).
- **Panes**: AppKit collapsing a pane by itself during a window's first
  layout is no longer taken as the user hiding it (it had turned the
  Inspector off and saved that); pane widths are restored only once the
  split view's frames have settled, retrying briefly after layout.
- **Tabs, frosted**: inactive tabs are frosted glass (`.ultraThinMaterial`)
  with a hairline edge; the active tab is solid, the card's color, with its
  icon in the accent color (gray on the others) and a semibold title. The file card's top-left
  corner is square and the first tab starts flush with it, so the tabs and
  the card read as one panel.
- **Sidebar, lighter**: the backdrop is washed toward white in light mode
  (the system sidebar material read too gray); dark outline icons with the
  accent only on the current destination and cloud services; quieter
  section labels; a soft neutral selection pill, with the focus ring only
  once the arrow keys are used; the startup disk shown as a small card
  ("254 GB of 494 GB used", gauge) whose gear holds Connect to Server and
  Settings.

### Inspector, Get Info–style

- Same top as the design (preview, icon/name/"Kind • Size", Share, Copy
  Path, More), with one accent **split Open button** for files and folders
  alike: "Open in <default app>" (a folder opens in place), and a chevron
  whose menu is built on click for the selected item — default app first,
  then the other apps macOS lists for that type (folders add Open in New
  Tab and Open in Terminal). SwiftUI's menu-button ignored the prominent
  style and kept a stale app list, hence the custom `SplitOpenButton`.
- **Details / More Info / Permissions** tabs of plain label–value rows
  (`InfoRow`), selectable:
  - Details: kind, size with exact bytes and on-disk size, item count and
    a Calculate button for folders, cloud status (only when macOS reports
    the item as iCloud/File Provider), created/modified/last
    opened/added, where (with Reveal), an alias/link's original, tags.
  - More Info (Spotlight metadata): dimensions, resolution, color space,
    duration, codecs, pages, title, authors, app version (falling back to
    the bundle), download source sites, Finder comment.
  - Permissions: owner (marked "you"), group, Read & Write / Read only /
    No Access for owner, group, everyone; locked; hidden extension.
- `ItemDetailsService` reads all of it off the main thread; new tests
  cover ownership/permissions/size on disk, locked files, symlink
  destinations, app version fallback, the access wording, and download
  source display.
- With nothing selected, the folder summary now refreshes when you move
  to another folder (it used to keep the previous folder's count).
- Not yet: editing tags or comments, and the design's Versions, Activity,
  Related Files, and AI tabs (no real data source).

### Command bar, selection-aware

- The row under the path bar stays calm: **New ▾** on the left; Sort ▾,
  Grid/List, Dual Pane, and **More ▾** (Compress, Extract, Calculate Size,
  Copy Path, Open in Terminal, View Options) on the right.
- Selecting items swaps New for a tinted strip: "N selected ✕ │ Copy · Cut
  · Rename · Share · Trash" (✕ deselects via
  `FileListViewModel.clearSelection()`; Rename with several items opens
  Batch Rename). Labels step off as the window narrows (`ViewThatFits`).
- A **Paste chip** ("Paste 2 items", or "Move 2 items here" after a Cut)
  appears only for what was copied or cut *in OneRoot this session*
  (`ClipboardTracker`, keyed to the clipboard's change count) — the shared
  system clipboard can hold files copied elsewhere or long ago, which ⌘V
  still pastes. It sits on the right so it doesn't move with the selection.

**Context Bar** — the name for the selection-aware row under the path:
- Nothing selected: New ▾ … Sort ▾, **View ▾** (its own menu now: Inspector,
  **Calculate Folder Sizes** — a one-off for the current view, never the
  setting — hidden files, columns), Grid/List, Dual
  Pane, **More ▾** — which acts on the *current folder* (Copy Folder Path,
  Open Folder in Terminal, New Folder, New File).
- Selection: Copy, Cut, Rename, Share, **Size** (folders; hidden when
  Settings ▸ General ▸ **Always calculate folder sizes** is on, as is the
  context menu's Calculate Size), Compress, Extract (archives), Copy
  Path(s), Terminal, Trash.
- **Esc** in the file list and **Edit ▸ Deselect All (⌥⌘A)** clear the
  selection, like the strip's ✕ (which now clears the view model at once).
- **Fix**: the selection no longer survives a folder change or the
  selected items being trashed. `reloadData()` kept the old selected row
  *numbers*, so other rows showed as selected and the view model never
  heard the selection changed; the list now always resets it to the items
  still present, and navigating clears it outright.
- **Quick Actions card removed** (the Context Bar covers it). The bottom
  tool row holds File Operations and is hidden by default (layouts from
  the previous build keep everything else, with the row hidden).
- Calculating folder sizes automatically is only ever turned on in
  Settings ▸ General; View ▸ Calculate Folder Sizes (main menu and the
  Context Bar's View ▾) sizes the folders in the current view once
  (`FileListViewModel.calculateFolderSizesInView`), and is hidden/disabled
  while the setting is on.


### UX Phase 3 — Breadcrumb and editable path control

- The path bar has two small buttons at its right end: **Edit Path**
  (pencil, same as ⇧⌘G or clicking empty space) and **Copy Path** (copies
  the folder's full path; shows a checkmark briefly).
- **Edit ▸ Copy Path (⌥⌘C)** copies the selected items' paths, or the
  current folder's when nothing is selected.
- VoiceOver labels for breadcrumb segments ("Go to Documents" / "Documents,
  current folder"), the › menus ("Subfolders of Documents"), and the …
  menu ("Earlier folders"); all are buttons reachable with full keyboard
  access.
- The editing logic lives in `AddressBarEditor` (a plain struct, unit
  tested): begin, Esc, Return with valid/invalid input, network connect
  and failure, the folder changing while typing, and switching tabs.
- **Fix**: switching tabs while typing a path now cancels the edit instead
  of carrying the half-typed text into the other tab.

### UX Phase 4 — File Inspector (finished)

- **Folder actions**: a selected folder's Inspector shows **New Tab** and
  **Pin / Unpin** (to the sidebar's Pinned section) beside Copy Path;
  Share moves into More for folders. Pins now match a folder whether its
  path ends in "/" or not.
- **Inspector tab per window tab**: Details / More Info / Permissions is
  remembered for each tab (`Tab.inspectorSection`), copied by Duplicate
  Tab, and saved with the session.
- **Edit tags**: the Tags row is always shown for a single item. Each tag
  has a remove button; **+ Add Tag** offers the standard color tags, the
  other tags used in this folder, and **New Tag…** (type, Return; Esc
  cancels). Tags are written off the main thread by `TagService`
  (`NSURL` `.tagNamesKey`); the folder reloads so the Tags column
  updates, and a failure puts the old tags back and shows why.
- Not done: editing Finder comments (Spotlight comments) — macOS only
  writes them reliably by scripting Finder, so they stay read-only.
  Tag changes aren't on the Undo stack.

### UX Phase 5 — File Operations Center (finished)

- **Recent operations**: the File Operations card lists what finished this
  session (newest first, up to 30) under its running operations — copies,
  moves, compressions, extractions — as Done, Cancelled, or failed, with
  the time. **Clear** empties the list; **×** removes one entry.
- **Error details**: a failure shows the error in red, and **Details**
  expands to how many items had finished, the system's reason and
  suggestion, and its error domain and code (selectable, for copying).
- **Retry** (copy and move): runs the operation again for only the items
  that hadn't finished — not ones you chose to Skip. Compress and extract
  failures have no Retry; running them again from the item is the same.
- **Failures aren't missed**: a failure while the card is out of sight
  puts "N failed" in the status line; clicking it shows the card.
- **Floating progress windows** now appear only when the front window
  isn't showing the File Operations card — the card has the same
  progress. Hiding the card while something runs brings its window up.
- **More detail** (card and floating window alike, `FileOperationText`):
  while running — bytes done of total, speed, time remaining once it's
  steady (after a few seconds and a few percent), "Item 2 of 4: “name”",
  and "From ~/Downloads to /Volumes/USB"; once finished — "Done · 4
  items, 3.4 GB in 42s", "Cancelled after 2 of 4 items · 1.1 GB of 3.4
  GB", or "Stopped after …" for a failure, the route, and **Show**, which
  opens the destination folder in a new tab.
- **Tabs** in the card, as in the design: **Active (n)**, **Completed
  (n)** (done and cancelled), **Errors (n)**; Clear empties the tab
  showing. Opened from "N failed", the card shows Errors.
- **Trash, Delete Immediately, Put Back and Empty Trash** are recorded
  too (the error dialog still appears). Move to Trash now goes on past an
  item it can't trash instead of stopping, so Undo and Put Back cover
  everything that did go; Retry trashes the rest. Delete Immediately has
  no Retry — deleting for good should be asked for again.
- **Fix — copies of Desktop, Documents, … couldn't be deleted**: macOS
  marks those folders "everyone: deny delete", and copying kept that
  rule, so the copy couldn't be trashed either. `FileCopier` now drops
  just that entry from every copied folder (other access rules are kept).
- The list is kept for the current run of the app only.

### UX Phase 7 — Quick Actions (image, PDF, and text transforms)

- **Quick Actions ▾** in the Context Bar's selection strip, **Quick
  Actions ▸** in the file list's context menu, and **File ▸ Quick
  Actions**: Resize Images, Convert Images (JPEG/PNG/HEIC/TIFF — only
  formats this Mac's ImageIO can write), Remove Metadata, Combine into
  PDF, Text to Markdown, Markdown to HTML, HTML to Markdown.
- Selection-capability model (`QuickActionCatalog`, from file types only):
  an action shows when it applies to some of the selection and is enabled
  only when it applies to all of it; otherwise it's disabled with the
  reason. Hidden in the Trash and for selections nothing applies to.
- Every action opens `QuickActionSheet` first: options plus a preview
  (`QuickActionPlanner`) of each output name, dimensions or page count,
  what's skipped and why, and warnings (lossy, transparency → white,
  first frame only). Image details are read off the main thread and the
  read is cancelled when the sheet closes.
- Never replaces anything: outputs go beside the originals ("photo
  (resized).jpg", "photo.png", "photo (no metadata).jpg", "Combined.pdf"),
  numbered " (2)" when taken, written to a scratch file and moved into
  place without overwriting (`SafeFileWriter`). New files are selected
  afterwards.
- Runs off the main thread (`QuickActionRunner`) as a File Operations
  entry (item by item, Cancel between items/frames); one Undo step
  trashes the outputs, including those finished before a failure or Cancel.
- Resize keeps every frame and never enlarges. Remove Metadata drops GPS,
  EXIF, IPTC, and XMP but keeps orientation; JPEG/PNG/TIFF are copied
  without re-encoding (pixel-identical, tested), others re-encoded at top
  quality. Combine uses PDFKit for PDFs (links/annotations kept) and Core
  Graphics for image pages (upright, at the image's own size); locked PDFs
  are left out and shown as such.
- **Text conversions** (`TextConversionService`), each written as a new
  UTF-8 file beside the original, with a preview of the first file's
  converted text in the sheet:
  - **Text to Markdown** — plain-text files (.txt, .log, …; not source
    code, JSON, CSV, or XML). Options: Keep line breaks (trailing double
    space), Show symbols as written (escapes `*`, `#`, `-`, …).
  - **Markdown to HTML** (`MarkdownHTMLRenderer`) — Foundation's own
    Markdown parser (tables, strikethrough, fenced code), rendered as a
    page titled by the first heading; optional light/dark styling. Raw
    HTML in the Markdown passes through. Foundation drops emphasis inside
    link text (`[go **now**](…)` → plain link text).
  - **HTML to Markdown** (`HTMLMarkdownConverter`) — Foundation's
    forgiving `XMLDocument` HTML parser; keeps headings, paragraphs,
    emphasis, links, images, lists, quotes, code, tables; drops layout,
    styles, scripts, forms. Text is decoded first (UTF-8, then
    Windows-1252/Mac Roman), since the parser loses accents when a page
    doesn't declare its encoding.
  - Files over 20 MB, or that aren't text, are skipped with the reason.
- Not done: rich text/Word to Markdown, PDF split/rotate/compress/OCR,
  and Quick Actions in the Inspector's multi-selection view.

### UX Phase 8 — Workspaces

- A **Workspace** is a named set of real folders for one project — say
  `~/repos/phoenix`, `~/Documents/Phoenix`, and `/Volumes/NAS/Phoenix
  Design`. It isn't a folder and doesn't merge or move anything.
- **Sidebar ▸ Workspaces** (below Special): each Workspace with its icon
  and folder count; **+** makes a new one. Choosing one takes the tab to
  its first folder that's there, and the hierarchy shows **every folder
  as its own root** (same-named folders get the folder they're in added,
  e.g. "Design (Archive)"; hovering a root shows its full path). Copy
  Path and Reveal in Finder work on each root as on any folder.
- The tab stays in the Workspace while you browse inside its folders;
  going anywhere else (or choosing a destination) ends it, and the
  hierarchy roots normally again. Each tab remembers its Workspace, and
  so does the saved session.
- **Edit** (right-click ▸ Edit Workspace…): name, icon, and folders —
  Add Folder… (OneRoot's own chooser), remove (the folder isn't
  touched), drag to reorder. Right-click also has Open in New Tab and
  Delete Workspace… (only the Workspace goes).
- **Adding folders**: drop folders on a Workspace in the sidebar (they're
  added as references — nothing moves), or Inspector ▸ More ▸ **Add to
  Workspace** for a selected folder (or New Workspace with it).
- **Workspace tabs** are named after the Workspace (not the folder
  you're in, which is in the tooltip) and share one Workspace icon, so
  one is recognizable from any other tab.
- **Add to Workspace** is also in the Context Bar's **More ▾** (for the
  folder you're in) and in the Inspector's folder summary (More), as well
  as Inspector ▸ More for a selected folder.
- Stored as JSON in user defaults (`WorkspaceService`, app-wide
  `WorkspaceStore`); not synced, no automatic project detection.

### UX Phase 9 — Search unification

- **One filter model** for the current folder and Advanced Search:
  `SearchCriteria`, gaining Kind (Visualize's `StorageCategory`),
  relative Date Modified (`SearchDateRange`: Today, This Week, This Month,
  This Year — stays relative in saved queries), and Tags (all of them).
  Older saved queries still decode. Matching lives in the tested
  `SearchCriteriaMatcher`, used by the folder filter and `SearchService`
  (name walk, Spotlight post-filter, content search) alike.
- **Folder filter**: the search field is still a live name filter; the
  filter button beside it adds Kind, Date Modified (presets or between
  dates), Size (presets or custom), Extension, Tag, Files/Folders only,
  and Name Options (Contains / Starts With / Ends With / Regex, Match
  Case). Active filters show as **chips** under the Context Bar
  (`FolderFilterBar`, `FilterChipBar`, wording in `SearchChipBuilder`):
  click to edit, ✕ to remove, match count, Clear. An unfinished regex
  turns the Name chip red and lists nothing. Filters stay on from folder
  to folder until Clear (the name filter used to clear on every
  navigation); they're per tab. Search Subfolders and Clear are bordered
  buttons.
- **Search Subfolders** (chip row, and View ▸ Search Subfolders with This
  Filter) hands the filter to Advanced Search rooted at the folder
  (`SearchHandoffCenter`), which takes it whether it was open or not and
  starts searching.
- **Advanced Search** keeps its form, modes (Name & Metadata, File
  Contents), regex, Spotlight, saved queries, export, streaming, and
  Cancel; a chip row above the results shows the criteria (including
  contents text, hidden files, cloud storage). Removing a chip restarts a
  running search; Add Filter is where Kind, relative dates, and Tags are
  set.
- View ▸ Clear Filters. Not done: typed filter syntax (`kind:image`) and
  natural-language queries (Phase 12).

### Tabs: close commands, next/previous, VoiceOver (#47, #42 items 1 and 3)

- Right-click a tab: Close Tab, Close Other Tabs, Close Tabs to the Right,
  Duplicate Tab, Move Tab to New Window, New Tab — for that tab, active or
  not (`TabDragHostView.menu(for:)`).
- View menu: Show Next Tab (⌃⇥) / Show Previous Tab (⌃⇧⇥), wrapping;
  Close Other Tabs (⌃⌘W; ⌥⌘W is macOS's Close All); Close Tabs to the Right (⌃⌥⌘W). Neither close
  command ever closes the window (`WindowViewModel.closeOtherTabs`,
  `closeTabsToTheRight`, `selectAdjacentTab`).
- VoiceOver: each tab is a "tab" (radio button) named after its folder
  (or "Workspace X, in folder"), with its selected state, Press to select,
  Show Menu, and Close / Close Other / Close to the Right actions; the
  strip is a "Tabs" group. Dual Pane headers read "Left pane, Documents"
  with their selected state and Press to focus.

### File Operations UX (#50, #49, #42 items 5, 6, 13)

- **Pause / Resume** (`PauseOperationButton`, beside Cancel) only for work
  that can really stop and carry on (`FileOperationProgress.pauseControl`):
  copies and cross-volume moves (`CancellationFlag` — `FileCopier`'s
  `copyfile` callback waits on it mid-file, file still open, and the item
  loop waits between items) and compress/extract (`ProcessHandle` sends
  `ditto`/`7z` SIGSTOP/SIGCONT; a later step's process starts stopped if
  paused — and a multi-item `ditto` compress stages its items through
  `FileCopier` with the handle's own `CancellationFlag`, so the staging
  copy pauses and cancels too). Paused time is left out of speed and time remaining
  (`activeElapsed`); the bar goes gray and still. Cancel while paused ends
  the pause first (wakes the copy, SIGCONT before SIGTERM), and so does
  Quit (`ArchiveProcessRegistry.terminateAll`). No Pause while preparing,
  or for Trash, rename, same-volume moves, or Quick Actions.

- A red **Cancel** button (`CancelOperationButton`) in the File Operations
  card and the floating progress windows, replacing the small ✕. Pressing
  it marks the operation `isCancelling` at once
  (`FileOperationProgressCenter.requestCancel`) — the button becomes
  "Cancelling…" with a spinner and can't be pressed twice — and VoiceOver
  says so.
- Cancelling (or a failure of) a compress or extract now removes the
  half-made archive or folder (always a new name of OneRoot's own).
- Settings ▸ General ▸ **Show progress in the window**: a new operation
  opens the front window's File Operations card, and no floating windows
  appear (unless no main window is open to show the card).
- Operation errors show in a red, dismissable banner above the status line
  (`OperationErrorBanner`) with Show Details, instead of replacing the
  status text; VoiceOver announces them.
- VoiceOver announces each finished, cancelled, or failed operation, once
  for the app (`FileOperationProgressCenter.announce`, set by
  `AppDelegate`).
- The icon-size slider is labeled "Icon size", and its end icons are hidden
  from VoiceOver.

### Inspector & tags (#52, #53)

- **Tag several items at once:** with several selected, the Inspector's
  `MultiTagEditor` lists their tags (`TagService.usage`) — "2 of 5" with
  Add to All for partial ones, ✕ to remove from all, Add Tag to All. The
  file list's context menu has **Tags ▸** (✓ all / – some; choosing adds to
  all, or removes if all have it). `FileListViewModel.setTag(_:adding:on:)`
  changes only that tag on each item, off the main thread; failures from
  the menu show in the error banner.
- **Markdown in the Inspector:** Raw | Rendered for `.md` files (raw by
  default, remembered in `com.oneroot.inspector.showsRenderedMarkdown`).
  Rendered is `MarkdownPreview`: `MarkdownHTMLRenderer` off the main
  thread into a `WKWebView` with JavaScript off; clicked links open in
  their own app.
- `FileItemActionsMenuTests` builds the real context menu and fires its
  Tags items the way AppKit does.

### Polish: storage bar, Advanced Search entry (#59, #58)

- The sidebar's storage bar is the accent color until the startup disk is
  80% used, orange from 80%, red from 90% (`VolumeSpace.level`); VoiceOver
  reads the percentage and "nearly full" / "almost out of space".
- Advanced Search no longer has its own magnifier button beside the
  search field (it read as the field's search button); it's the last item
  of the field's filter menu (≡), plus ⌥⌘/ and View ▸ Advanced Search.

### Documents to PDF (#54)

- **Convert to PDF** Quick Action for Word (.doc/.docx/.wordml), RTF/RTFD,
  OpenDocument text, and plain-text files; **Combine into PDF** takes them
  too (each printed to PDF first, in the chosen order).
- `DocumentPDFRenderer` (a documented AppKit boundary in the service
  layer): reads with `NSAttributedString` off the main thread, lays out in
  an `NSTextView` and prints to PDF with `NSPrintOperation` on the main
  thread — TextEdit's fidelity: text, fonts, styles, lists, tables,
  pictures; not Word's page layout (headers/footers, columns, text
  boxes). Default paper size, ¾-inch margins, top-aligned. Never
  overwrites (`SafeFileWriter`); progress, Cancel, and Undo as for the
  other Quick Actions. Pages documents aren't readable without Pages.
- No third-party converter; LibreOffice or Word would do better layout
  but aren't system frameworks.

### Recents, Shared, and Workspace search (#48, #55)

- **Recents** and **Shared** in the destinations sidebar, under Home.
  They show in the file list like a folder but aren't one: a
  `VirtualLocation` (its own `oneroot:` URL, so history, Back/Forward,
  tabs, Duplicate Tab, and the saved session record it), listed by
  `VirtualListingService` off the main thread. `currentDirectory` is `nil`
  meanwhile — Paste, New, Up, Search Subfolders, and watching are off; the
  hierarchy is left as it was.
  - Recents: Spotlight's last-opened dates, last 30 days, files in your
    home (not ~/Library or hidden), newest first (at most 500). Sorts by
    Date Last Opened while shown, then puts the folder sort back.
  - Shared: iCloud Drive items whose `ubiquitousItemIsShared` is set (a
    shared folder is listed itself). iCloud only — other providers don't
    report sharing; the empty state says so.
  - A **Where** column (`FileColumn.location`, also an ordinary optional
    column) is added automatically there, after Name.
  - Recents is ordered and dated by Spotlight's `kMDItemLastUsedDate`
    (Finder's), via `SpotlightIndex.recentlyUsed`, and includes iCloud
    Drive and `~/Library/CloudStorage`. A File Provider that keeps its own
    index (Nextcloud) isn't visible to Spotlight, so its files can be in
    Finder's Recents and not OneRoot's.
- Recents always opens sorted by Date Last Opened, newest first. While
  Recents/Shared is shown the folder hierarchy closes
  (`WindowViewModel.setShowingList`, driven by the focused pane's
  `virtualLocation`) and reopens on leaving, unless it was closed by hand.
- **Friendly dates** (Settings ▸ General ▸ Friendly dates, off by
  default): `FileDateFormat` (relative `DateFormatter`) for
  every date column, the Inspector, and search results; exports and
  Terminal commands keep plain dates.
- **Date Last Opened source** (Settings ▸ General, off by default): off,
  the column shows the file's access time (`contentAccessDate`, updated by
  anything that reads the file); on, `FileSystemService.listDirectory`
  asks Spotlight for each item's last-used date (Finder's), which costs a
  lookup per item as a folder loads. Toggling reloads open lists.
- **Workspace search:** `SearchCriteria.additionalRoots` (+
  `workspaceName`); `searchRoots` drops duplicates and folders inside
  others. `SearchService` searches each in turn with running counts and
  skips folders that are gone. The filter row in a Workspace tab has
  **Search Workspace**; Advanced Search has **Workspace ▾**; Show as
  Terminal Command lists every folder.

### UX Phase 10 — Visualize

- A **Visualize** card in the bottom tool row (⌃⌘B), beside File
  Operations, shows what's taking space in the focused pane's folder —
  everything inside it, hidden files and package contents included — and
  follows you as you browse.
- **Folders**: a treemap of the folder's items (folders blue, files gray;
  items under 1% fold into "N more items") beside the same items as a
  list with sizes and shares. Click a folder to open it, a file to select
  it in the list.
- **Types** (images, video, audio, documents, archives, apps, code,
  other), **Age** (this week / month / year / older, by last modified),
  **Tags** (each in its Finder color, plus untagged) and **Cloud**
  (downloaded / cloud-only / not in the cloud): a stacked bar and a list
  of the groups; choose one to see its largest files, and click a file
  to find it in the list.
- **Scanning** (`StorageScanner`) runs off the main thread and updates
  the card as it goes; Stop keeps what's counted so far, Rescan starts
  over. Going to another folder cancels the scan in progress; folders
  scanned this session show again at once. Nothing is scanned while the
  card is hidden. Symbolic links aren't followed; a package (an app, a
  library) counts as one item of its kind; unreadable folders are
  counted ("N couldn't be read") and skipped; cloud placeholders are
  read without downloading anything.
- Colors: a validated colorblind-safe palette in a fixed order per kind
  (separate light and dark steps); every chart has a labeled list beside
  it, so color never carries meaning alone.

### UX Phase 11 — Help

- **Help ▸ OneRoot Help (⌘?)** is brought up to date with everything
  built since it was written (it still described a Quick Actions card):
  21 topics in five groups — Basics, Browsing, Working with Files,
  Connecting, Customizing. New topics: **Coming from Windows**, Workspaces,
  Dual Pane, The Context Bar, The Inspector, File Operations (the card),
  and Visualize.
- **Coming from Windows** maps Explorer's names and keys to OneRoot's
  (Properties → Inspector, drive letters → Locations and `/Volumes`,
  Recycle Bin → Trash, Map network drive → Connect to Server, Ctrl → ⌘,
  F2 → Return, …) and lists what works differently (Return renames, apps
  are bundles, eject before unplugging). It's also directly in the Help
  menu. There are no in-app hint popups.
- **Search** (the field above the topic list): every word has to appear
  in a topic's title, text, or hidden keywords (so "Properties" or
  "Recycle Bin" find the right topic), ignoring case and accents. Title
  matches are listed first, each with an excerpt, and the matches are
  highlighted in the topic. `HelpSearch`, unit tested.
- **See Also** links at the end of each topic; Keyboard Shortcuts is now
  in sections, the same ones as the ⌘B popover (which gained ⌘Y, ⌘⌫ and ⌘?).
- **? buttons** open the matching topic: each Settings pane, Batch
  Rename, Connect to Server, Copy via SSH, the Workspace editor, Advanced
  Search, and the File Operations and Visualize cards (`HelpButton`,
  `HelpNavigator` — the one Help window picks the topic up whether it was
  open already or not).
- Content lives in `HelpContent` (a plain model with stable
  `HelpTopicID`s), separate from the view.

### Name conflicts: one question, Replace goes to the Trash

- A copy or move now finds every name collision **before anything is
  copied** (`FileSystemService.conflicts(for:in:)`, off the main thread)
  and asks about all of them at once through
  `resolveConflicts: (FileConflictRequest) async -> FileConflictAnswer`.
  The answer is a choice per item (`.resolve([source: resolution])`, with
  anything missing treated as Skip) or `.cancel`, which copies/moves
  nothing. A collision that only appears once the operation is under way
  (two selected items with the same name from different folders, or
  something created meanwhile) is asked about on its own; cancelling that
  stops the operation like the progress popup's Cancel. The old per-name
  `onConflict:` API is kept as a wrapper.
- **One collision** shows the same Replace / Keep Both / Skip alert as
  before. **Several** show `FileConflictSheet`: "N of M items already
  exist in “folder”" with Replace All, Keep Both, Skip All, Cancel, and
  **Choose for Each…** — a list with both versions' modified date and size
  (files only; folders aren't sized), the newer side marked, a per-item
  picker starting at Skip, Set all to Replace / Keep Both / Skip, and
  **Replace Older**. Used by the file list (both Dual Pane panes) and the
  folder hierarchy, for paste, drag and drop, and F5/F6.
- Each view model queues its questions (`FileConflictQueue`), so two
  operations waiting at once each get their own answer, and a dialog
  closing after its button already answered can't answer the next one.
- **Replace moves the existing item to the Trash** instead of deleting it.
  The new item is still staged under a hidden name first; only once it's
  complete is the old item trashed and the new one renamed into place (if
  that rename fails, the old item comes back out of the Trash). The change
  log records `.trashed(original:trashedAt:)` before the copy/move, so
  **Undo** takes the new item away and then puts the old one back, and the
  Trash view's Put Back knows where it came from. On a volume with no
  Trash (most network shares) Replace falls back to the old behavior:
  renamed aside, deleted once the new item is in place, not undoable.
- `FileSystemService.trashItem` is injectable; the copy/move tests use a
  fake Trash in a temp folder. `FileConflictTests` covers the single
  up-front question, per-item answers, missing answers, Cancel (copy and
  move), no question when nothing collides, mid-operation collisions,
  Replace to Trash and its change log (copy and move), the no-Trash
  fallback, a failed copy leaving the original untouched, the newer-side
  comparison, metadata, and the queue.

### Merge folders, ⌃-drop menu, Copy Name (#62, #68, #69)

- **Merge** (`FileConflictResolution.merge`) is offered when a folder meets
  a folder of the same name (`FileConflictItem.canMerge`: both ordinary
  folders, never packages). The single alert puts Merge first for folders;
  the sheet adds **Merge All** when every conflict is a folder, **Merge
  Folders** in Set all to, and Merge in each folder row's picker. Merging
  copies/moves the folder's contents into the existing one through the
  same per-item path as the top level (`transfer` / `mergeContents` in
  `performFileOperation`): one up-front question for everything inside
  that collides, Merge again for folders inside, Replace still to the
  Trash. `.DS_Store` is left out. A move then trashes the emptied source
  folder (logged last, so Undo puts the folder back before moving the
  files into it); if anything was skipped the source folder stays.
  Merge chosen for something that isn't two folders is skipped.
- **⌃-drop menu** (`DropActionMenu`): holding ⌃ while dropping on the
  file list (list or grid) or the folder hierarchy shows **Move Here /
  Copy Here / Make Alias Here / Cancel** at the pointer, after the drop has
  finished. ⌃ narrows the drag to Link, so validate methods propose Link
  while it's held. A true right-drag isn't possible without delaying every
  right-click menu to mouse-up, so this is the macOS-shaped version; it
  works for drags from Finder too. Not on breadcrumbs, destinations, or
  tabs (SwiftUI drop delegates can't propose Link).
- **Make Alias Here**: `FileSystemService.makeAliases(to:in:)` writes
  Finder alias files (bookmark data), named "name alias", "name alias 2", …;
  each is undoable as a created item.
- **Copy Name / Copy Name without Extension** (`CopyableName`): right-click
  menu in the list (any number of items; the second only when it would
  differ), Copy Name in the hierarchy's menu, and both in the Edit menu.
  Folders keep their whole name ("v1.2"); packages lose theirs like files.
- Tests: `MergeAliasAndNameTests` (merge offered only for folders, contents
  merged with one inner question, change log, move-merge trashing the
  emptied folder last, skipped items keeping the source, Cancel inside a
  merge, Merge on files skipped, alias naming and resolution, alias
  errors, name text and when "without Extension" is offered).

### Compare Panes (#63)

- With Dual Pane on: **Compare** (⇄ in the Context Bar) or **View ▸ Compare
  Panes**. `FolderComparisonService` walks both folders off the main
  thread (cancellable, progress every 250 items), comparing by name, size,
  and modification date within a second; contents aren't read. Each top
  item gets a `ComparisonStatus` per side: same, only here, newer here,
  older here, or differs (both sides changed, same date but different
  size, or file vs folder). Folders sum up what's inside. `.DS_Store` is
  ignored, symlinks aren't followed, unreadable folders count as differs
  and are counted in the bar.
- `PaneComparison` (owned by the `Tab`) pushes statuses into both panes'
  `FileListViewModel.comparisonStatuses`; the list's Name cell shows a
  word label (Newer / Only here / Older / Differs, colored but never color
  alone, with a tooltip). **Differences Only** sets `comparisonFilter`.
  The comparison ends when either pane navigates, or on swap, close, or
  tear-off.
- **Copy to Right / Left** shows `PaneSyncSheet` first (the items, and the
  files left alone because they differ without being newer), then copies
  through the normal `transfer` with `FolderComparisonService.syncAnswer`
  answering conflicts: merge folders, replace only with a newer file (old
  one to the Trash), skip the rest. Nothing is deleted; Undo works as for
  any copy; the comparison reruns afterwards. Copies keep modification
  dates (`COPYFILE_ALL`), so synced files compare as the same.
- Labels appear in list view only; grid view shows the bar but no per-item
  labels. No checksum comparison yet (#64).
- Tests: `FolderComparisonTests` (statuses on both sides, one-second
  tolerance, folder roll-up, file vs folder, identical, cancellation, what
  Copy sends, the sync answers, an end-to-end Copy to Right that loses
  nothing, and the view model marking, filtering, and ending on
  navigation).

### Verify copies and one copy per disk at a time (#64)

- **Settings ▸ General ▸ Verify copies** (off by default,
  `FileVerifier.enabledKey`): after an item is copied to another disk —
  copy, cross-disk move, Replace's staged copy, each item inside a Merge —
  `FileVerifier` reads the copy and the original back with `F_NOCACHE`
  (so it checks the disk, not the write cache) and compares them byte for
  byte, folders item by item and symlinks by target. A mismatch removes
  the copy (ours, just made) and fails the item with the usual Retry; a
  move deletes its original only after the copy passes. Copies within one
  disk are APFS clones sharing the original's data and aren't checked. The
  progress shows "Verifying the copy…" (`FileOperationProgress.isVerifying`).
- **Settings ▸ General ▸ Copy to the same disk one at a time** (on by
  default, `FileTransferQueue.enabledKey`): a copy/move that moves data
  between disks (`FileTransferQueue.disks(for:into:)` — mount points;
  empty when everything is on the destination's disk) waits in
  `FileTransferQueue` until nothing ahead of it shares a disk. The waiting
  operation's progress says so and has **Start Now** (and Cancel, which
  leaves the line). First come, first served; unrelated disks run side by
  side.
- `FileSystemService` gained `verifiesCopies`, `queuesTransfers`,
  `transferQueue`, and (tests only) `verifiesSameDiskCopies`; item
  operations now take an `ItemContext`.
- Tests: `VerifyAndQueueTests` (matching files and folders over several
  chunks, a changed byte, a different length, a missing item, symlink
  targets, cancellation, a verified copy end to end, same-disk work never
  queued, overlapping disks waiting while unrelated ones don't, Start Now,
  and Cancel while waiting).
- Not tested automatically: a real copy to another disk (the tests' folders
  are all on one disk).

### Faster copies to NFS shares (#65, first step)

- Measured on an NFSv3 share (TrueNAS) with a folder of 1,537 mostly small
  downloaded files: every file carried quarantine/provenance/"Where from"
  extended attributes, which NFSv3 can't store, so macOS wrote a hidden
  `._name` file per item and took ~15 NLM lock round trips per file.
- `FileCopier.storesMetadataNatively` asks the volume
  (`getattrlist` `VOL_CAP_INT_EXTENDED_ATTR`; NFS doesn't report it). For
  destinations without it, copies use `COPYFILE_DATA | COPYFILE_STAT`
  (contents, permissions, owner, dates) instead of `COPYFILE_ALL`, unless
  **Settings ▸ General ▸ Keep Mac metadata on NFS shares** is on. Disks and
  SMB shares always get everything.
- Result on the same share over Wi-Fi, 150 files / 43 MB: 195.8 s with
  everything, 98.8 s without — about 2×. The remaining ~0.66 s per file is
  network latency (Wi-Fi to the NAS averaged 26 ms per round trip, and NFS
  needs several per file; an empty file took ~235 ms to create).
- Tests: metadata left off when the destination can't store it, kept on
  disks and when the setting asks, and the boot disk reporting native
  support.
- **Speed and time left use the last ten seconds** (`FileOperationProgress
  .rateSamples` / `recentRate`), falling back to the average only for the
  first few seconds; pausing and the start of the transfer reset the
  readings, and a copy with no progress for a whole window shows no speed.
  The average since the start drifted for minutes when a copy went from
  large files to thousands of small ones.

### Show All Files in Subfolders (#66)

- **View ▸ Show All Files in Subfolders** (also the Context Bar's View
  menu): `FileListViewModel.setShowsAllFilesInSubfolders` lists every file
  under the folder — not folders, not package insides — through
  `FileSystemService.listAllFiles(under:includeHidden:limit:onBatch:)`, a
  cancellable walk that fills the list in batches and stops at 50,000
  files. Where is shown, a `FlatViewBar` under the Context Bar says what's
  listed and has Show Folders; going to another folder turns it off; a
  refresh re-walks and swaps the list at the end. `WindowMenuState`
  mirrors it for the menu checkmark. Tests: `FlatViewTests`.

### Names Windows-style destinations reject (#70)

- `NameCompatibility`: for SMB shares and FAT/exFAT/NTFS drives
  (`volumeTypeName`), finds names with `\ : * ? " < > |`, control
  characters, a trailing space or period, or a reserved device name
  (CON, NUL, COM1…), inside folders too, and proposes fixes ("_" for bad
  characters; collisions get " (2)"). NFS and Mac disks are never checked.
- Before a copy/move there (`NameFixCheck`, both view models),
  `NameFixSheet` lists old → new names: **Rename Copies** (default),
  **Skip These**, or Cancel. `copyItems`/`moveItems` take `nameFixes` and
  `skipping`; folders with a renamed or skipped item inside are made and
  filled item by item (`foldersContaining`), the made folder logged first
  so Undo removes it last. `PromptQueue` now backs both the conflict and
  the name questions. Tests: `NameCompatibilityTests`.

### Find Duplicates (#67)

- **View ▸ Find Duplicates…** (the current folder, both with Dual Pane on)
  and **More ▸ Find Duplicates…** open a window (`DuplicatesView`,
  handed folders through `DuplicatesHandoffCenter`). `DuplicateFinder`
  groups files by size, then by a SHA-256 of the first 4 KB, and reads in
  full only what still matches; skips empty files, links, package insides,
  hidden files, and second hard links to one file (device + inode).
  Cancellable with progress; biggest savings first, oldest copy first.
- Mark copies (Mark All but Oldest/Newest); the last copy of a set can't
  be marked. Move to Trash confirms, records origins for Put Back, and is
  undoable. Rows: Open, Show in OneRoot, Reveal in Finder, Copy Path.
  Tests: `DuplicateFinderTests`.

### Large-folder benchmark (#72)

- `Scripts/benchmark.sh` runs `LargeFolderBenchmarkTests` (skipped in
  normal runs; enabled with `ONEROOT_BENCHMARK=1`): list and open a
  50,000-file folder (with and without Spotlight dates), sort, filter, the
  flat view, Compare Panes, and Find Duplicates on 20,000-file trees, each
  against a generous budget, and appends the timings to
  `Benchmarks/history.csv`. `Scripts/release.sh` runs it first
  (`SKIP_BENCHMARK=1` to skip).
- First run found that Settings ▸ General ▸ "Date Last Opened: use
  Spotlight's date" made every listing — the file list, the folder tree,
  the file chooser — ask Spotlight about every item: 16–22 s for 50,000
  files. `listDirectory(_:includeHidden:wantsLastOpenedDates:)` now asks
  only when the file list shows, sorts, or groups by Date Last Opened
  (`needsLastOpenedDates`; it re-reads when that becomes true), and runs
  the lookups in parallel: 2.9 s without, 7.0 s with, in a Debug build.

### Check for Updates (#36)

- `UpdateChecker` asks GitHub's releases API
  (`hillcraft-sc/OneRoot/releases/latest`), ignores drafts and
  pre-releases, compares versions numerically, and picks the `.dmg` asset.
  `UpdateCenter` checks at launch at most once a day when **Settings ▸
  General ▸ Check for updates automatically** is on (off by default) and
  **OneRoot ▸ Check for Updates…** any time; the **Software Update** window
  (`UpdateView`) shows the notes, Download (the disk image, in the
  browser), Later, and Skip This Version. Nothing is downloaded or
  installed by OneRoot. Not during unit tests. `docs/PRIVACY.md` now
  describes the request. Tests: `UpdateCheckerTests` (no network).

### Duplicate (⌘D)

- **File ▸ Duplicate** (⌘D) and the right-click menu: `FileListViewModel
  .duplicate` copies each selected item into its own folder through the
  normal copy path (so "name (2)", progress, one Undo step), grouped by
  folder for Recents and the flat view, then selects the copies. Not in
  the Trash. Test: `DuplicateCommandTests`.

### Linux port, phase 1: OneRootCore (#78)

- `Package.swift` builds **OneRootCore** (module `OneRoot`): 79 platform-neutral
  files (models, services, and the few view-model helpers with no UI) and 22
  test files, listed explicitly. These are the same files the Xcode app
  compiles; the Mac app doesn't depend on the package and is unchanged
  (722 tests). Compiling the shared files twice, instead of the app
  importing a module, avoids making about 70 files' types `public`. The
  Linux app will compile the same files the same way.
- `swift test` runs the 145 shared tests on macOS; `Scripts/test-linux.sh`
  runs them in the OrbStack Linux machines (Ubuntu 24.04, Debian 12 and
  13, Arch); all pass.
- Changes to make the files portable (the Mac behavior is identical):
  - `CancellationFlag`/`PauseControl` moved out of `FileCopier.swift`;
    `TrashResult`/`FileSystemError` out of `FileSystemService.swift`;
    `StorageCategory` out of `StorageReport.swift` (its UTType mapping stays
    there as an extension).
  - Linux-only imports where Foundation is split up: `FoundationXML`
    (`HTMLMarkdownConverter`), `FoundationNetworking` (`UpdateChecker`).
  - Markdown on Linux uses Apple's open-source **swift-markdown** (Linux
    only; approved): `MarkdownHTMLRenderer` renders with its HTML formatter
    and `HelpSearch` reads plain text with it. macOS keeps Foundation's
    parser.
  - `NameCompatibility` finds FAT/exFAT/NTFS/SMB destinations on Linux from
    `/proc/self/mounts`; `FileVerifier` drops the page cache with
    `posix_fadvise(DONTNEED)` where macOS uses `F_NOCACHE`.
- Not shared yet (platform seams, phases #79–#80): `FileSystemService` and
  what depends on it (copy, trash, undo, archives, Quick Actions), Spotlight,
  volumes, and every view model that uses Combine.
- Name sorting: a precomputed Finder-style key was 10× faster on Linux but
  gave a different order from Finder's in 269 of 7,101 real folders
  (punctuation). The Mac app keeps `localizedStandardCompare`; the Linux app
  will sort with GLib's `g_utf8_collate_key_for_filename`, the order Nautilus
  uses.

### Linux port, phase 2: platform seams (#79)

- **`Platform`** is the one place shared code asks the operating system for
  what differs: Trash, copying an item (with progress and Cancel), whether
  a volume stores extended attributes, Spotlight's last-opened date,
  aliases, the search index, file kinds by extension, "is this a text
  file", and where progress is shown. `MacPlatform.swift` (`#if os(macOS)`)
  calls the code that was already there — `FileManager.trashItem`,
  `FileCopier`, `SpotlightIndex`, UTType, `FileOperationProgressCenter`;
  `LinuxPlatform.swift` (`#if os(Linux)`) has first versions: no Trash yet,
  `FileManager.copyItem`, symbolic links for aliases (refusing a missing
  target, like an alias), no index (search walks the folders), a common
  extensions table, a UTF-8 text sniff, and a silent progress reporter.
  The real Linux versions are phase 4 (#81).
- **`FileOperationProgressReporting`**: services report progress through
  this protocol instead of `FileOperationProgressCenter.shared`; the center
  conforms. `ProgressReporter` and the shared labels
  (`FileOperationLabels`) moved with it.
- Now shared (95 files): `FileSystemService` (copy, move, merge, replace,
  verify, the per-disk queue, aliases, trash), `FileUndoService`,
  `SearchService`, `SearchCriteriaMatcher`, `VirtualListingService`,
  `DuplicateFinder` (CryptoKit on macOS, swift-crypto on Linux),
  `ArchiveService`, `SafeFileWriter`, `TrashFallback`, `FileTransferQueue`.
  `FileCopier`, `SpotlightIndex`, and `FileOperationProgressCenter` are in
  the package wrapped in `#if os(macOS)`, so `swift test` on macOS runs
  the same code the app does.
- Small moves: the search-index protocols got their own file;
  `StorageCategory.of(UTType)` lives in `MacPlatform.swift`; `goneCount` is
  `TrashFallback`'s; content search reads lines with `FileHandle.bytes` on
  macOS and from the whole (size-limited) file on Linux.
- Tests: 297 shared tests pass on macOS; 267 on Ubuntu 24.04, Debian 12,
  Debian 13, and Arch, with 7 skipped there until phase 4 (archives via
  `ditto`, the Trash) through `skipOnLinuxUntilPhase4`. Tests of macOS-only
  behavior (Finder aliases, extended attributes, iCloud placeholders,
  Finder-hidden folders, the progress windows, `FileCopier`) are fenced
  `#if os(macOS)`. Mac app: 722 tests pass.
- Moved to phase 3 (#80): file watching, volumes, tags, item details,
  credentials, the clipboard, and confirmations — their interfaces are
  Combine publishers or live in view models, so they change with the
  Combine-to-Observation work.


### Linux port, phase 6: folder hierarchy and Inspector (#82)

- **Folder hierarchy pane** (`Linux/…/HierarchyPane.swift`): the shared
  `FolderHierarchyViewModel` and `HierarchyCoordinator` (unchanged) root a
  lazily loaded folder tree at the tab's destination, or at a Workspace's
  folders. The rows are a flattened list (indent + disclosure button), not
  a GTK `TreeListModel`. Clicking navigates, middle-click opens a new tab,
  the right-click menu has Open, Open in New Tab, Copy Path and Reload; the
  tree follows the current folder and re-reads folders the file watcher
  reports. Hidden folders follow the Show Hidden Files setting.
- **Inspector** (`InspectorPane.swift`, `ItemInfo.swift`): preview and
  properties of the selection in the focused pane. Images (up to 25 MB)
  and the first lines of text files are previewed; everything else shows
  its icon. Properties are what Foundation can read reliably — kind, size
  and size on disk, location, modified and accessed dates, owner, group,
  permissions, link target, folder item count, tags. No creation date
  (Linux doesn't expose a reliable one here). No selection shows the
  current folder; several items show a count and total size. Reads are
  cancelled and stale answers dropped when the selection changes; denied
  and vanished items say so. Open, Open With, Open in New Tab, Pin and
  Copy Path use the window's existing actions.
- **Layout**: the shared `WindowLayoutModel` is now used on Linux — the
  sidebar, hierarchy and Inspector toggle from the header bar (F9,
  Shift+F9, Ctrl+I) and their widths are saved with `WindowLayoutService`,
  so the next window opens the same way.
- **Drag and drop** (`DragAndDrop.swift`): rows in the file list and the
  hierarchy drag out with the whole selection (a `GdkFileList`, which other
  apps get as `text/uri-list`), and files dropped on a folder row, on empty
  list space (into the folder shown), on a hierarchy row or on a sidebar
  folder destination are copied or moved through the shared
  `FileListViewModel.handleDrop`, so conflicts, name fixes, progress and
  Undo are the ones paste uses. A drag within one filesystem moves, across
  filesystems copies; Ctrl forces a copy and Shift a move. A folder can't
  be dropped into itself, and the Trash and Recents don't take drops.
  Folders dropped on a Workspace (or on the empty Workspaces hint) are added
  to it (or start one). Tested in a virtual display with scripted drags
  (list → folder row, list → tree row).
- **Narrow windows** hide panes by `WindowLayout.fitted` (Inspector first,
  then hierarchy, then sidebar) and bring them back when the window widens;
  the saved layout is not changed.
- **Inspector sections and tags**: Details / More Info / Permissions
  switcher (kept while the selection changes), and tag chips with remove
  buttons plus an Add a tag field, written to `user.xdg.tags` off the main
  thread (a failure is shown and the chips revert).
- Not done yet: image decoding happens on the main thread (hence the size
  cap), and dropping onto the Trash (move to Trash) isn't wired. The narrow
  window (the Inspector hid at a narrow width and returned on widening), the
  section switcher and tag editing (two tags added in a row, `user.xdg.tags`
  checked on disk) were checked in a virtual display (Xvfb) with scripted
  clicks and keys. Removing a tag and the failure message weren't exercised.

### Linux port: search field and filter chips

- **Filter bar** (`Linux/…/FilterBar.swift`) above each pane's file list:
  Ctrl+F or `/` opens it (also main menu ▸ Filter This Folder); Escape
  clears the text, then closes the bar. It edits the pane's
  `FileListViewModel.filter` — the same `SearchCriteria` the Mac uses — so
  matching, the unfinished-regex error and the empty "No Matches" state are
  the shared ones. The filter stays on from folder to folder until Clear.
- **Chips** come from the shared `SearchChipBuilder` (Kind, Modified, Size,
  Extension, Tag, Files/Folders, and Name when it needs more than plain
  "contains"). Click a chip to edit it, ✕ to remove it; the match count and
  Clear sit at the end of the row. **Add Filter** lists Kind, Date Modified,
  Size, Extension, Tag, Files or Folders and Name Options; each editor stays
  open so several kinds, extensions or tags can be ticked in one go.
- **Search Subfolders** (in the chip row) hands the folder's filter to
  Advanced Search, which searches that folder and everything in it.
- **Advanced Search** (`AdvancedSearchWindow.swift`, Ctrl+Shift+F or main
  menu ▸ Advanced Search…): one window over the shared `SearchViewModel` and
  `SearchService`. Name & Metadata or File Contents, a name/text field with
  Contains / Starts With / Ends With / Regex and Match case, Include hidden
  files, Search in (Choose… or Entire File System), and the same chips and
  Add Filter as a folder's. Results stream into a list (Name, Match line in
  contents mode, Location, Size, Modified) with a running count and scan
  totals; Search turns into Cancel; changing a chip restarts a running
  search. Double-click opens a file (a folder shows in a file window);
  Show in Folder opens the result's folder in a new tab.
- Not done on Linux: Workspace search, Spotlight-style indexing (full scan
  only), regex suggestions, between-dates filters (relative ranges only),
  saved queries, Show as Terminal Command, Export. Checked in a virtual
  display (Xvfb) by scripted keys and clicks, and no shared code changed, so
  the shared tests are unchanged.

### Linux port, phase 6: packaging (#83), first slice

- **Build fix**: the app didn't compile against glib 2.90 (Arch) because
  `G_APPLICATION_HANDLES_OPEN` is imported differently; it now uses
  `GApplicationFlags(rawValue:)`. Release builds checked on Arch and Ubuntu 24.04.
- **`Scripts/release-linux.sh <version>`** builds a stripped binary with the Swift
  runtime linked statically (`--static-swift-stdlib`) in an OrbStack machine and
  writes `build/release/OneRoot-<version>-linux-<arch>.tar.gz` plus its sha256
  (25 MB). The binary resolves all libraries on Arch and Ubuntu 24.04 (checked
  with `ldd`; not launched there).
- **`Linux/packaging/`**: desktop entry, AppStream metainfo, icon, an
  `oneroot-bin` PKGBUILD and a Flatpak manifest (app id
  `com.hillcraft_sc.OneRoot`).
- Needs libadwaita **1.7+** and GtkSourceView 5 (found when installing the
  packages on real distros; Ubuntu 24.04 and Debian 12 are too old).
  Since then: x86_64 tarball, `.deb` and `.rpm` packages, `install.sh`, and a
  separate `linux-v0.1.0` pre-release (`Scripts/publish-linux-github.sh`) are
  done; the PKGBUILD builds on Arch; the Flatpak builds and runs on aarch64.
  Not done: Flathub submission, the AUR push, an apt/dnf repository.

### Linux port: File Operations panel (L1)

Copies, moves, compress and extract now show their progress in the Linux app. A File Operations panel sits above the status bar (Ctrl+Shift+O, View menu, or the "File Operations" button at the right of the status bar, which also shows how many are running or failed). It lists each running operation with its item, bytes done of total, speed and time left, a Pause/Resume and a Cancel button, and Start Now for a copy waiting behind another to the same disk; finished ones stay under it with their result and a Retry for those that failed. The panel opens itself when an operation starts and closes after a few seconds if everything succeeded; it stays open for a failure or when you opened it yourself. Two options sit at its bottom: Verify copies and Copy to the same disk one at a time (the same settings keys as the Mac's Settings, until the Linux Settings window exists). Quitting (Ctrl+Q, or closing the last window) while an operation runs asks first. Copy errors now carry the system's own reason ("Permission denied", "No space left on device") instead of a generic write error.

It is the shared `FileOperationProgressCenter` the Mac uses, so behavior matches; `FileOperationText` moved into the shared core with a Linux path for the time formatting (Foundation on Linux has no `DateComponentsFormatter`). Verified headless (`Scripts/linux-ui-check.sh operations`): a 20,000-file copy with Pause, Resume and Cancel (the partial copy is removed), a failure with Retry, and Verify copies across filesystems. Not yet checked: Orca reading of the panel, a removable drive, and a GtkPaned layout warning seen with the panel open during long copies (logged in `docs/LINUX-DEV.md`). Linux is still the 0.1.0 prototype.

### Linux port: Settings and themes (L2)

The Linux app has a Settings dialog (Ctrl+,, or the main menu) with four pages. **General:** Verify copies, Copy to the same disk one at a time, Friendly dates, Always calculate folder sizes, Warn before closing the last tab (Ctrl+W and the tab's close button now ask before closing the last tab, as on the Mac), and Clear Navigation History. **Appearance:** OneRoot (Automatic, the default, light or dark with the desktop), System (Automatic, plain libadwaita), OneRoot Light and Dark, Catppuccin, Gruvbox, Nord and Tokyo Night. A theme colors the window, bars, file list, sidebar, accent, selection and the sidebar's icons; folder and file icons in the list come from the icon theme and keep their look. **Archives:** format (Zip or 7z) and where Compress saves (next to the items, one folder, or ask each time). **Terminal:** the command Open in Terminal runs (empty = `$TERMINAL`, then the first installed known terminal); it shows what is in use.

The shared `ThemeStore` now builds on Linux (its AppKit parts are behind `#if os(macOS)`; the Linux app supplies libadwaita's color-scheme hooks), and `ThemeTests` joined the package tests. **Bug found and fixed:** on Linux `UserDefaults` only reaches disk at `synchronize()`, and nothing called it, so no preference (including the window layout) survived a restart. The app now saves every two seconds and at quit. Verified headless: each page, switching themes (OneRoot Dark, Catppuccin Frappé, System) and the theme being remembered after a restart, the last-tab warning, and the Terminal status line. Not covered: Orca, high contrast and Reduce Motion with themes, and theme contrast on real hardware. Linux is still the 0.1.0 prototype.


### Linux port: Dual Pane and Compare Panes (L3)

The Linux app can split a tab into two panes: **Ctrl+\\**, the header's Dual Pane button, or the main menu. The new pane opens at the same folder; the focused pane has an accent edge, **Ctrl+`** switches panes, **Swap Panes** (main menu) exchanges them, and **F5 / F6** copy or move the selection to the other pane. **Compare Panes** (Ctrl+Alt+\\, or the main menu; only while split) compares the two folders, subfolders included, by name, size and date, and writes each item's status (Newer, Older, Only here, Differs) next to its name in both lists. A bar above the panes shows what differs on each side, a Differences Only filter, **Copy to Left / Right** (a preview of exactly what will be copied comes first; nothing is deleted or overwritten when newer, and replaced files go to the Trash), Compare Again and Done. Navigating either pane, swapping or closing the split ends the comparison. The Dual Pane toggle is now in the Context Bar (L6). At about 900 px wide with the sidebar, hierarchy and Inspector all open, the split is wider than the window (L9).

### Linux port: Find Duplicates and Visualize (L4)

**Find Duplicates** (Ctrl+Shift+D, or the main menu) opens its own window that scans the current folder, subfolders included; with Dual Pane on it scans both folders. Identical files are listed in sets with a checkbox on each copy; one copy of every set can't be marked, so one always stays. Mark All but Oldest / Mark All but Newest / Clear help with big lists, and Move to Trash (after the usual confirmation, recorded for Undo) removes the marked copies from the list as they go. Right-click a row for Open, Show in Folder (a new tab in the file window) and Copy Path; double-click opens the file. It is the shared `DuplicateFinder` and `DuplicatesViewModel`, with SHA-256 from swift-crypto on Linux.

**Visualize** (Ctrl+Alt+V, or the main menu) is a panel above the status bar that scans the folder you're in, only while it is open, and follows the folder as you browse. Folders lists the folder's items by size; Types, Age, Tags and Cloud list the groups, and clicking a group shows its largest files. Clicking a folder goes into it; clicking a file selects it in its folder. Stop keeps what has been counted; the refresh button scans again. Every row shows its size as text next to its bar. Not done on Linux: the treemap and the stacked colored bars (the bars are one accent color, and rows are keyboard-focusable buttons instead).

Verified headless (`Scripts/linux-ui-check.sh duplicates`, `duplicates-mark`, `visualize`, light and dark): sets found across subfolders, marking, confirming and trashing, then an empty result; Visualize Folders and Types. Not yet checked: Orca, a 100,000-file folder, a removable drive. Linux is still the 0.1.0 prototype.

### Linux port: Advanced Search extras, Workspaces and batch rename (L5)

**Advanced Search** has a Saved & Scope menu in its header: Save Current Query… names the filters for later, saved queries load with one click and can be deleted, Search a Workspace points the search at all of a Workspace’s folders at once, and Show as Terminal Command… shows (and copies) the same search as a command line. Export… at the bottom writes the results as CSV, plain text, Markdown or interactive HTML to a file you name. Still missing: regex hints and the between-dates filter.

**Workspaces** can now be made and managed: the + beside Workspaces in the sidebar, Ctrl+Alt+N, or New Workspace… in the main menu opens an editor for the name and folders (Add Folder…, Remove, Up/Down). Right-click a Workspace for Open, Open in New Tab, Edit and Delete (its folders are never touched); right-click a pinned folder for Remove from Sidebar. A folder’s More menu has Add to Workspace. Icons and drag-to-reorder aren’t on Linux yet.

**Batch rename**: select two or more items and press F2 (or Rename). Choose Replace Text (with regular expressions and case), Add Text, Format (numbering, start and digits) or Change Case; a live preview shows every new name and flags clashes, empty names and the like, and Rename is off until nothing clashes. It is all or nothing and undoable as one step, via the shared `BatchRenameService`.

Verified headless (`Scripts/linux-ui-check.sh search-extras`, `workspaces`, `batchrename`): the menu, a result list and its Export button, the new-Workspace editor and the new sidebar row, and a four-file rename. Not checked: Orca, the Export file dialog and a saved query round-trip on a real desktop, and renaming thousands of files. Linux is still the 0.1.0 prototype.

### Linux port: Context Bar, Grid view, Help and Inspector details (L6)

The **Context Bar** is a row under the tabs. With nothing selected it offers **New** (folder, file, folder and open); with a selection, that selection's actions: Open, Open in New Tab (folders), Cut, Copy, Rename, Compress, Extract (archives) and Move to Trash, or Restore and Delete Permanently inside the Trash. A **Paste** chip appears on the right while the clipboard holds files. Always there: **Sort**, the **List / Grid** switch, **Dual Pane** (moved here from the header), and **More** (Select All, Duplicate, Copy Path, Open in Terminal, Pin, Show Hidden Files, Calculate Folder Sizes, Find Duplicates, Visualize Storage, Advanced Search). Each button runs a window action, so it greys out when the action doesn't apply; buttons are icon-only with tooltips and accessible labels.

**Grid view** (Ctrl+1; Ctrl+2 for List) shows the folder as icons with names, remembered per folder through the shared `FolderViewModeService`. It shares the list's selection, right-click menu, drag and drop and keyboard. Icons are a fixed 64 px (no size slider yet).

**Help** (F1 or main menu ▸ Help) is a window with a topic list, search and 11 topics written for the Linux app; **Ctrl+?** opens its Keyboard Shortcuts topic. The Mac's help text is Mac-specific, so Linux has its own (`LinuxHelpContent`, `LinuxShortcuts`) over the shared topic model and `HelpSearch`.

The **Inspector** shows **Created** where the filesystem records a birth time, and decodes image previews in a background task instead of on the main thread (images up to 200 MB). Files can be dropped on the sidebar's **Trash** row to trash them.

Not done: the icon-size slider, a Compare Panes button in the bar, collapsing the bar in a narrow window (its left buttons scroll sideways instead), the quick shortcut popover, and the Mac's Ctrl-drop menu (Ctrl copies and Shift moves, as in Nautilus). Verified headless (`Scripts/linux-ui-check.sh contextbar`, `help`, light and dark, and 900x700): the bar with and without a selection, the Paste chip, Grid and back to List, Help start, search ("rename") and shortcuts, the Created row and image preview. **Not verified:** dropping on the Trash row (the harness can't drag), Orca, a large folder in Grid, and the 900 px layout, where the window is still wider than the screen (the L9 item). Linux is still the 0.1.0 prototype.

### Linux port: Quick Actions (L7)

Select images, PDFs or text files and use **Quick Actions** in the Context Bar (it appears when something applies) or in the right-click menu. Each action opens a sheet that lists every file with what will happen to it and what it will be called; files are always written **beside the originals as new files** (` (2)` names, never replacing), with a File Operations entry (Cancel) and Undo that removes what was made.

- **Resize Images** (longest side or percentage; never enlarges), **Convert Images** (JPEG, PNG, TIFF; transparency becomes white for JPEG), **Remove Metadata** (JPEG and PNG byte for byte minus EXIF, GPS, IPTC, XMP and comments, orientation kept; other formats are re-encoded).
- **Combine into PDF** (PDFs, images and text files in an order you set, with Up/Down per row; password-protected PDFs are refused) and **Convert to PDF** (plain text, A4 or Letter by locale, monospaced).
- **Text to Markdown**, **Markdown to HTML**, **HTML to Markdown**, with a preview of the first file.

It uses the same planner, runner and sheet model as the Mac, over a new `QuickActionServices` seam: ImageIO/PDFKit/TextEdit on the Mac, GdkPixbuf, **qpdf** (new, Linux only; approved for L7) and Cairo/Pango on Linux. Differences: resized and converted copies have no metadata (GdkPixbuf writes none); animated images and multi-page TIFFs keep the first frame; HEIC can't be written; Word, RTF and OpenDocument aren't converted. The Mac's behavior is unchanged (584 package tests and the Quick Action tests in Xcode pass).

Verified headless (`Scripts/linux-ui-check.sh quickactions`, `quickactions-combine`, `quickactions-text`; light, dark and 900x700): the menu on a selection, Resize (real 50% run: new file listed, selected, File Operations entry and toast), Convert, Combine (real run: a 1.1 MB PDF), and the text sheets with preview. Unit tests (52 Linux, 565 core on each distro the script runs) cover the byte-level metadata reader/stripper with synthetic JPEGs (GPS, XMP, IPTC, truncated files), GdkPixbuf resize/convert, qpdf merge with page counts, text to PDF, and which actions each selection offers. **Not verified:** the Flatpak build (needs a qpdf module, L10), the new .deb/.rpm/Arch dependency names on clean machines, Orca, very large images or PDFs, real camera EXIF, and metadata after pixel data in a PNG. Linux is still the 0.1.0 prototype.


### Linux port: sessions, Recents, SSH and network shares (L8)

- **Reopen last session.** Windows, tabs, split panes, sort orders, pane layout and window size come back at launch (Settings ▸ General ▸ Reopen windows and tabs from last session, on by default). The shared `SessionService` stores it and makes it safe (a folder that's gone opens Home); it's saved every two seconds when something changed and at quit, so a crash loses little. Window *position* isn't restored (GTK4 doesn't let apps place windows). Launching with files (`oneroot ~/folder`) opens those instead. Fix found on the way: a restored split in a background tab no longer opens with its first pane collapsed.
- **Recents** in the sidebar: the files you opened in the last 30 days, newest first, read from `~/.local/share/recently-used.xbel` (`$XDG_DATA_HOME`) by the new core `RecentlyUsedIndex`. Missing files are left out; anywhere on disk counts (other drives too); OneRoot only reads the list. There is no Shared list on Linux (it's iCloud Drive's). The address bar and sidebar show Recents as a place, not a path.
- **Connect to Server** (Ctrl+K, main menu, Context Bar ▸ More): smb://, nfs://, sftp://, ftp://, dav:// through GIO/GVfs with a `GMountOperation` (`NetworkMounter`), then opened in the active tab. Optional user name and password; a refused login says so instead of retrying; a dead server gives up after 60 s. Favorite servers use the shared `SavedServersService`; a remembered login goes to the desktop keyring, never to OneRoot's settings. Typing an address in the address bar mounts it the same way (no login). Needs gvfs-fuse to show the share as a folder; without it OneRoot says "Connected, but can't browse it".
- **Copy via SSH** (right-click ▸ More, or the main menu): the shared `SSHCopyService` (scp, with askpass for a password) behind a GTK dialog with saved destinations, key picker and "remember in keyring". **Settings ▸ SSH** adds, edits and removes destinations and can Install Key on Server (`ssh-copy-id`). No Touch ID gate (Mac-only). Copy shows a toast when it starts and ends; scp gives no progress, so none is drawn.
- **Keyring**: new **libsecret** system library (`CLibSecret`, Linux only, approved for L8) behind `KeyringService`; without a Secret Service the "remember" switch reports it instead of failing silently.

Verified headless against a local sshd and Samba (see `docs/LINUX-DEV.md`): the SSH copy landed on the server; Connect to Server mounted the share with the right password and said "didn't accept that user name and password" for a wrong one; Recents listed only the fresh, existing files; a three-tab session with a split came back after a restart. Not verifiable in the container: browsing the mounted share (no FUSE) and the keyring through the GUI (the store/lookup/replace/remove round trip passes against a real GNOME Keyring in `KeyringServiceTests`). The package tests pass (588 on macOS, 569 on Linux with 2 skipped), as do the Linux UI-logic tests; the Mac app builds.

### Linux: narrow windows, accessibility labels and edge states (L9)

The Linux window can now be narrowed to about 470 px: the Inspector, then the folder hierarchy, then the sidebar hide as the window gets too narrow for a 360 px file list (they come back when it widens; your chosen layout isn't changed). Back, Forward, Up, New Tab, the main menu, Type a Path and Eject have accessible names, as do the file list, sidebar and hierarchy list. A folder that takes more than 0.3 s to read shows "Loading…", and the Inspector says when a folder can't be read instead of "0 items".

Verified headless (`Scripts/linux-ui-check.sh narrow`, `states`, `hidpi`): 700 px light and dark with Dual Pane, 2x scale, a 20,000-file folder (Select All, End), permission-denied, empty and deleted-while-open folders. **Not verified:** Orca (no AT-SPI in the harness), a real removable drive, and the "Loading…" page (no slow folder to test it with). Linux is still the 0.1.0 prototype.

### Linux: update check and release scripts (L10)

A copy of OneRoot for Linux installed from the tarball with `install.sh` can look for newer Linux releases: Settings ▸ General ▸ Updates has Check Now and an automatic once-a-day check (off by default). It asks GitHub for the release list, sends nothing about you or your files, and only links to a newer release; nothing is downloaded or installed. Copies installed from a package (.deb, .rpm, Flatpak, AUR) don't show it, because the package manager updates them. The Mac's update check now also reads the release list, so Linux releases never show up in it.

For the maintainer: `Scripts/release-linux-all.sh` and `Scripts/build-linux-repos.sh` build the release files and signed apt/dnf repositories locally; neither publishes. **Not done:** a real signing key and hosting, the Flathub source build, the AUR push, and the 1.0.0 version (the app and metainfo still say 0.1.0 prototype until you sign off). Verified headless (`Scripts/linux-ui-check.sh updates`, `updates-packaged`): the group is shown for a tarball install and absent otherwise, and Check Now against the real releases repo reports no stable Linux release yet. **Not verified:** an update actually being found (no stable Linux release exists), and the automatic check's toast. Linux is still the 0.1.0 prototype.
