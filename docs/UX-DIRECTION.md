# OneRoot UX direction (moved from CLAUDE.md §6)

Target UX structure and interaction requirements. Phases 0–11 are built; README.md records what exists. Read the relevant subsection before changing that area.

## 6. Target UX structure and interaction requirements

### 6.1 The core mental model

The redesign should organize OneRoot around four distinct questions:

```text
Destinations -> Hierarchy -> Contents -> Context
```

- **Destinations:** Where do I want to work?
- **Hierarchy:** Where am I inside that location or project?
- **Contents:** What is in the selected folder?
- **Context:** What can I learn or do with the current selection?

The present OneRoot sidebar combines global destinations and arbitrary-depth folder navigation. The redesign must separate those responsibilities without discarding the existing tree implementation.

The intended desktop composition is:

```text
+--------------------------------------------------------------------------+
| OneRoot   [Tab] [Tab] [Tab] [+]                                         |
+----------------+-------------------+----------------------+---------------+
| GLOBAL         | FOLDER HIERARCHY  | FILE LIST            | INSPECTOR     |
| DESTINATIONS   |                   |                      |               |
|                |                   |                      | Preview       |
| Home           | selected root     | Name                 | Properties    |
| Recents        | +- folder         | Date Modified        | Activity      |
| Starred        | +- folder         | Size                 | Actions       |
| Pinned         | |  +- folder      | Kind                 |               |
| Cloud          | +- folder         |                      |               |
| Locations      |                   |                      |               |
| Workspaces     |                   |                      |               |
+----------------+-------------------+----------------------+---------------+
| Status, or one expanded contextual tool                                  |
| File Operations | Dual Pane | Visualize | Quick Actions                  |
+--------------------------------------------------------------------------+
```

This is not four mandatory permanent panes. The hierarchy, Inspector, and bottom contextual workspace must be independently collapsible. The application must remain practical on a laptop display.

### 6.2 Global destination sidebar

Create a new shallow SwiftUI sidebar whose job is global navigation, not recursive filesystem browsing.

Initial sections should derive from capabilities OneRoot already has:

```text
HOME
  Home
  Recents
  Starred, when implemented

PINNED
  Downloads
  Documents
  user-pinned locations

CLOUD
  iCloud Drive
  Nextcloud
  other detected File Provider locations

LOCATIONS
  Macintosh HD
  Applications
  user home
  mounted or network locations

SPECIAL
  Trash

WORKSPACES
  Project Phoenix
  Personal
  + New Workspace
```

Rules:

- Do not allow arbitrary-depth folder expansion in the global sidebar.
- Keep section identity and ordering stable.
- Do not duplicate a location unnecessarily between sections unless the duplication has a clear user benefit.
- Use native-looking, restrained icons. Do not use red or warning-colored symbols for ordinary navigation.
- Selecting a destination sets or changes the root represented in the hierarchy pane and navigates the active tab appropriately.
- Right-click actions must remain relevant to the destination type.
- Preserve existing pinning, cloud-location detection, mounted-volume handling, network shares, Trash behavior, and live updates.

The global sidebar should be implemented in SwiftUI unless repository inspection uncovers a specific behavior that makes AppKit materially safer.

### 6.3 Dedicated folder hierarchy pane

Reposition the existing AppKit `NSOutlineView` as the dedicated folder-hierarchy pane.

The hierarchy pane answers:

> Where am I inside the current destination, volume, pinned location, or Workspace?

Examples:

```text
HOME ROOT

v user
  > Applications
  > Documents
  > Desktop
  > Documents
  > Downloads
  > Movies
  > Music
```

```text
WORKSPACE ROOT

v Project Phoenix
  v Documents
    > Requirements
    > Notes
  v Design
    > Mockups
    > Final
  > Reference
  > Exports
  > Repository
```

Requirements:

- Preserve lazy child loading, stable node identity, expansion state, context menus, drag and drop, filesystem watching, and tree-to-list synchronization.
- Show folders and hierarchy roots, not ordinary files.
- Root the hierarchy at the selected global destination or nearest meaningful context instead of always exposing the entire filesystem from `/`.
- A normal destination usually supplies one hierarchy root.
- A Workspace may supply multiple clearly labeled roots from different real locations.
- Never imply that Workspace roots share one physical parent.
- Offer Copy Path and Reveal Real Location for logical Workspace entries.
- The pane must be resizable and collapsible.
- Persist width and visibility at least per window.
- Preserve selected node and expansion state per tab or per hierarchy context where practical.
- Do not add expandable folders inside the primary file table as part of this redesign. The dedicated hierarchy pane provides that behavior more honestly and with less risk.

### 6.4 Primary file list

Keep the existing AppKit `NSTableView` as the primary contents view. It already owns mature behavior including columns, sorting, selection, keyboard commands, Quick Look, context menus, file operations, drag and drop, and state restoration.

The file list should answer:

> What is inside the folder selected in the hierarchy or current tab?

Requirements:

- Preserve customizable columns and saved column order.
- Preserve all current file operations and Trash-specific behavior.
- Preserve native multi-selection, keyboard behavior, drag and drop, Quick Look, and external refresh.
- Refine presentation without weakening density or performance.
- Use a calmer default column set: Name, Date Modified, Size, and Kind.
- Keep Date Created, Date Added, Date Last Opened, Tags, and Extension available but not necessarily visible by default.
- Use restrained separators and spacing.
- Consider a row height around 28-30 points if it remains comfortable and performant.
- Allow Name to flex while metadata columns use sensible bounded widths.
- Do not replace the file list with cards, a canvas, an AI conversation, or a spatial metaphor.

### 6.5 SwiftUI and AppKit boundary

Treat the AppKit tree and file table as specialized controls with narrow contracts.

A control should conceptually receive typed input such as:

```text
items
selection
sort state
column preferences
display options
root/context
```

A control should emit typed actions such as:

```text
selection changed
open requested
rename requested
context action requested
drop performed
expansion changed
```

The AppKit controls must not directly own or understand:

- Inspector presentation;
- bottom-workspace presentation;
- Windows transition guidance;
- Workspaces beyond the hierarchy roots supplied to the tree;
- AI or intelligent assistance;
- unrelated window chrome.

Avoid adding another collection of bespoke callbacks, notification names, and request counters when a focused typed adapter or existing view model can express the boundary. However, do not rewrite stable communication solely to satisfy an abstract architectural preference.

### 6.6 Tabs as persistent work contexts

Retain the existing custom tab system and refine its visual presentation.

A tab should preserve, where reliable:

- current directory;
- back/forward history;
- destination/hierarchy context;
- selected item URLs;
- scroll position;
- sort state;
- quick-search/filter state;
- hierarchy expansion relevant to the tab;
- Inspector visibility and selected Inspector section;
- optional contextual-workspace state.

Visual requirements:

- use tighter tab padding than the current wide strip;
- show a location/folder icon where useful;
- distinguish the active tab without a large heavy blue rectangle;
- show close controls on the active tab, hover, or keyboard focus;
- truncate long labels intelligently;
- provide overflow behavior when many tabs are open;
- preserve drag-hover tab activation;
- retain new-tab and close-tab keyboard behavior.

Possible later features:

- Reopen Closed Tab;
- Duplicate Tab;
- Pin Tab;
- Move Tab to New Window;
- save tabs as a Workspace.

### 6.7 Breadcrumb and editable path experience

Keep the current path field and autocomplete behavior, but change the default presentation to clickable breadcrumbs.

Example:

```text
Macintosh HD > Users > user > Desktop
```

Requirements:

- Breadcrumbs and direct path entry are two presentations of the same navigation state.
- Clicking a segment navigates to that folder.
- Clicking an edit affordance, clicking suitable empty path-bar space, or invoking a keyboard command enters raw editable-path mode.
- Preserve absolute paths, `~`, mounted paths, network URLs, inline validation, and folder autocomplete.
- Preserve a clear way to copy the complete path.
- Do not open a modal Go to Folder sheet for normal path entry.
- Exiting edit mode must not navigate unless the submitted path is valid.

### 6.8 Toolbar and command hierarchy

The current control rows are functional but visually dense. Refine the hierarchy into three understandable bands:

```text
Tabs
Location: Back / Forward / Up / Breadcrumbs / Search
Actions: New / Cut / Copy / Paste / Rename / Trash / Sort / View / More
```

Rules:

- Use monochrome/native foreground styling for ordinary commands.
- Reserve red for destructive actions such as Trash or Delete Immediately.
- Do not place warning-colored circles around Cut, Copy, Paste, Rename, Sort, or View.
- Group related operations and use separators sparingly.
- Disable unavailable actions instead of presenting ambiguous failures.
- Keep less-common commands in a More menu or contextual surfaces.
- Preserve main-menu commands and keyboard equivalents.
- Do not reintroduce menu instability by publishing frequently changing SwiftUI state directly into command/menu construction. Respect the existing `WindowMenuState` lessons documented in the repository.

### 6.9 File Inspector

Add a collapsible, resizable SwiftUI Inspector on the right side. Selection should provide useful context without opening another window.

Initial sections:

- Preview
- Properties

Add Activity only for information OneRoot can reliably record. Defer Versions, related files, and intelligent insights until a trustworthy data source exists.

For a selected file, show when available:

- large Quick Look-compatible preview;
- icon and display name;
- kind and size;
- Open and Open With;
- Share where supported;
- Copy Path;
- real location;
- created and modified dates;
- relevant dimensions or document metadata;
- tags;
- local/cloud availability state when reliable.

For a folder, useful actions can include:

- Open in New Tab;
- Pin or Remove from Sidebar;
- Add to Workspace;
- Open in Terminal;
- Copy Path;
- Calculate Size as an explicit cancellable operation.

Requirements:

- selection-driven metadata and preview loading must be cancellable;
- stale asynchronous results must never overwrite the current selection;
- the Inspector must support empty, loading, permission-denied, unsupported-preview, and multiple-selection states;
- the Inspector must be resizable and collapsible;
- persist visibility and width per window or as a documented app preference;
- do not fabricate versions, activity, authorship, cloud state, or related files.

When no item is selected, the Inspector may show a restrained current-folder summary. Do not place promotional cards in the file list.

### 6.10 Status bar and contextual workspace

Retain the useful compact status bar when no advanced tool is active:

```text
6 items, 1 folder, 5 files          241.81 GB available of 494.35 GB
```

Allow that lower area to expand into one contextual tool at a time:

- File Operations;
- Dual Pane;
- Visualize;
- Quick Actions.

Requirements:

- ordinary browsing should keep the area collapsed;
- collapsing the area must not cancel active work;
- do not display four simultaneous dashboard cards;
- ensure the expanded surface has keyboard focus behavior and accessible controls;
- preserve a compact summary when collapsed, such as active-operation count and progress state.

### 6.11 File Operations Center

Build on the existing operation-progress infrastructure.

Show, when genuinely available:

- operation type;
- source;
- destination;
- current item;
- item or byte progress;
- honest indeterminate state when byte progress is unavailable;
- estimated remaining time only when reasonably stable;
- cancel;
- pause only when the underlying implementation truly supports safe pause/resume;
- retry for recoverable failures;
- clear error details;
- recent completed operations;
- safe Undo where OneRoot has sufficient information.

Treat reversibility as a product principle, but fail safely. Undo must never overwrite unrelated data or assume a disconnected/cloud destination is unchanged.

Begin Undo with one low-risk operation type and tested validation rules before generalizing it.

### 6.12 Dual Pane

Dual Pane should be an on-demand task surface, not the default layout.

Initial scope:

- two independent locations;
- independent selection, sorting, and navigation;
- explicit Copy to Other Pane and Move to Other Pane;
- drag and drop between panes;
- obvious active-pane focus;
- optional Swap Panes;
- no automatic synchronization in the first release.

Reuse the existing AppKit file-list component with separate view-model instances instead of creating a second file-list implementation.

### 6.13 Workspaces

A Workspace is a project-oriented collection of references, not a folder and not an opaque virtual filesystem.

Example:

```text
Project Phoenix
  Documents  -> ~/Documents/Projects/Phoenix
  Design     -> OneDrive/Clients/Phoenix/Design
  Reference  -> Google Drive/Phoenix
  Exports    -> /Volumes/External/Phoenix
  Repository -> ~/repos/Phoenix
```

Initial scope:

- name;
- optional icon/color;
- ordered list of real referenced locations;
- persisted configuration;
- open a referenced location in current or new tab;
- Copy Path and Reveal Real Location;
- multiple hierarchy roots when the Workspace is selected.

Do not begin with automatic project detection, background synchronization, merged-file semantics, or AI organization.

### 6.14 Search as a visible query system

Retain the current-folder quick search and Advanced Search. Improve them through a shared understandable filtering model rather than a third unrelated search experience.

A future criteria model should cover:

- name;
- files/folders;
- extension or type;
- content;
- size;
- modified/created date;
- tags;
- hidden state;
- root/location;
- cloud/local state where reliably available.

Natural-language input can be added later, but the interpretation must be visible as editable filters.

Example:

```text
screenshots modified this month larger than 5 MB
```

```text
[Type: Image x] [Name: Screenshot x] [Modified: This Month x] [Size: >5 MB x]
```

Never make AI the only way to build or understand a query. Preserve streaming results and cancellation for recursive search.

### 6.15 Contextual Quick Actions

Quick Actions should adapt to the complete selection.

Examples:

- images: Resize, Convert Format, Remove Metadata, Combine into PDF;
- PDFs: Combine, Split, Rotate, Compress, OCR where a system-supported approach is chosen;
- folders: Compare, Calculate Size, Compress, Pin, Add to Workspace;
- multiple items: Batch Rename, Compress, Copy Paths.

Rules:

- show actions that apply to the complete selection, or clearly explain partial applicability;
- preview destructive, lossy, or batch transformations;
- keep actions out of the permanent toolbar unless frequently used;
- use system frameworks where practical;
- do not add third-party processing dependencies without approval.

### 6.16 Visualize

Implement storage visualization only after a reliable cancellable scanning service exists.

Potential views:

```text
Folders | File Types | Tags | Age | Cloud/Local
```

Requirements:

- incremental progress;
- cancellation;
- no main-thread recursive scans;
- safe handling of permissions, packages, symlinks, cloud placeholders, network latency, and disconnected shares;
- accessible list representation in addition to a treemap;
- selecting a category filters or navigates the main file list rather than opening a disconnected experience.

### 6.17 Windows-to-Mac transition layer

**Superseded (2026-10-30):** no contextual hints in the UI. The same
guidance lives in the Help documentation instead — see Phase 11 in §11.
The text below is kept for reference.

#### Original direction

OneRoot should understand Windows expectations while teaching macOS conventions.

Examples:

```text
Looking for Properties?
Use the OneRoot Inspector. macOS traditionally calls this Get Info.
```

```text
Looking for C:\?
macOS uses mounted volumes and paths instead of drive letters.
```

Guidance must be contextual, dismissible, disableable, and progressively reduced. Do not create a long first-run tutorial carousel.

Retain discoverable explicit actions such as Move, Copy, Rename, Trash, path entry, and useful context menus.

### 6.18 Cloud state clarity

OneRoot already recognizes File Provider and mounted cloud locations. Improve status only when reliable metadata exists.

Possible states:

- local;
- cloud-only;
- downloading;
- uploading;
- synchronized;
- unavailable;
- error;
- shared;
- available offline.

Do not infer provider state from an ambiguous icon. Provide text, tooltip, or accessible description. Do not pretend all providers expose the same capabilities.

### 6.19 Optional intelligent assistance

AI is not required for the core redesign. Do not implement it until deterministic browsing, search, metadata, operations, and previews are excellent.

If added later, AI should translate requests into visible searches or proposed operations. Any mutation must show affected items, allow exclusions, require approval, create an operation log, and support safe Undo where feasible.

Do not silently reorganize the filesystem.

---

---

# Moved from CLAUDE.md (§5, §7, §8, §10)

## 5. Product vision

OneRoot should be a **modern file-management workspace**, not merely Finder with extra buttons and not Windows File Explorer painted with macOS materials.

The intended reaction is:

> I already know how to use this, but it lets me do things Finder and Explorer make unnecessarily difficult.

The normal file browser remains conventional and calm. Innovation should surround that core and become visible when the user needs it.

### Three-layer interaction model

#### Layer 1: Familiar

The default experience should provide predictable navigation:

- sidebar
- file list
- tabs
- back, forward, and up
- visible path or breadcrumbs
- sortable columns
- drag and drop
- complete context menus
- familiar keyboard behavior

A Windows user should be productive quickly without sitting through onboarding.

#### Layer 2: Powerful

OneRoot should improve everyday file work through:

- persistent tab context
- clearer previews and metadata
- improved path navigation
- strong search and visible filtering
- cloud/local state clarity
- Workspaces
- operation history and recoverability

#### Layer 3: On-demand superpowers

Advanced tools should appear when relevant and collapse afterward:

- File Operations Center
- Dual Pane
- batch tools
- storage visualization
- compare/synchronize workflows
- contextual Quick Actions
- optional intelligent assistance

Do not make users permanently live inside a dense power-user interface.

---

## 7. Visual design direction

OneRoot should look native and polished without becoming a Finder clone.

### Principles

- The files are the content; chrome should recede during normal use.
- Prefer clear hierarchy over decorative cards.
- Use restrained macOS materials and translucency.
- Use color primarily for state, selection, tags, warnings, and visualization.
- Keep primary actions obvious and secondary actions discoverable.
- Support light and dark appearances deliberately.
- Support increased contrast, Reduce Transparency, and Reduce Motion.
- Allow comfortable density without forcing oversized touch-oriented controls on desktop users.
- Preserve native focus rings, keyboard traversal, VoiceOver labels, menu commands, and pointer targets.

### Default composition

The target layout is:

```text
+--------------------------------------------------------------------------+
| OneRoot   [Home] [Desktop] [Downloads] [Project] [+]                     |
+----------------+-------------------+----------------------+---------------+
| Global         | Folder hierarchy  | File list            | Inspector     |
| destinations   |                   |                      |               |
|                | current root      | Name                 | Preview       |
| Home           | +- folder         | Modified             | Properties    |
| Recents        | |  +- folder      | Size                 | Activity      |
| Pinned         | +- folder         | Kind                 | Actions       |
| Cloud          |                   |                      |               |
| Locations      |                   |                      |               |
| Workspaces     |                   |                      |               |
+----------------+-------------------+----------------------+---------------+
| Compact status or one expanded contextual tool                           |
+--------------------------------------------------------------------------+
```

The target is not a literal pixel-for-pixel copy of the concept art. Preserve macOS conventions, adapt to actual OneRoot capabilities, and keep the layout usable at smaller window sizes.

### Visual refinements from the current OneRoot screenshots

- Replace the single everything-tree with the shallow global sidebar plus dedicated hierarchy pane.
- Reduce the heavy top chrome by creating clear tab, location, and action bands.
- Replace red-outlined ordinary command icons with restrained native coloring; reserve red for destructive actions.
- Use breadcrumbs by default while retaining raw path editing.
- Make active tabs clear without a large heavy blue block.
- Use consistent spacing, corner radii, materials, icon scale, and alignment.
- Make the Inspector useful rather than filling empty file-list space with decorative content.
- Keep the normal file view dense enough for desktop productivity.
- Use color mainly for selection, tags, state, warnings, and visualization.
- Design light and dark appearances intentionally.
- Respect Increase Contrast, Reduce Transparency, and Reduce Motion.

The files remain the content. The interface should recede during normal browsing.

---

## 8. Accessibility and interaction quality

Every new feature must account for:

- full keyboard operation
- VoiceOver labels and logical traversal order
- visible keyboard focus
- sufficient contrast
- Reduce Motion
- Reduce Transparency
- large text where layout permits
- meaningful empty, loading, error, and permission-denied states
- context-menu and main-menu discoverability for important actions

Do not rely on hover as the only way to discover or invoke an essential action.

Animations should communicate cause and effect, such as opening the Inspector or expanding the operations area. Avoid decorative motion that slows repeated work.

---

## 10. Testing requirements

### Unit tests

Prioritize services and view models. Add or update tests for:

- path parsing and navigation
- directory listing and sorting
- selection/state preservation
- Workspace persistence and path resolution
- operation records and Undo validation
- copy/move/rename/Trash conflict handling
- search filters and query translation
- recursive scanners, cancellation, symlink handling, and permission failures
- Dual Pane view-model isolation
- cloud-state mapping where provider metadata is abstracted
- preference persistence

Use temporary directories and injected protocols/fakes. Tests must not watch or mutate the developer's real home folder, mounted shares, cloud locations, or Trash unless a narrowly scoped integration test explicitly requires it.

### UI and manual verification

For each UX phase, provide exact manual checks, including:

- light and dark appearance
- keyboard-only flow
- VoiceOver labels for new controls
- small and large window sizes
- local folder
- large folder
- removable volume where relevant
- disconnected or slow network location where relevant
- permission-denied path
- multiple tabs and windows
- active drag and drop where relevant

### Regression discipline

Before calling a phase done:

- the project builds;
- existing tests pass;
- new tests pass;
- unrelated behavior remains intact;
- no new main-thread filesystem work is introduced;
- documentation reflects the actual implementation, not the intended implementation.

---

