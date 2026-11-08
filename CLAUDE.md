# CLAUDE.md - OneRoot Development Instructions

## 0. Purpose of this file

This file is the operating instruction set for Claude Code when working on **OneRoot**, an already-built native macOS file manager.

The work is not a rewrite and not another attempt to clone Windows Explorer; the product vision is in `docs/UX-DIRECTION.md` (§5).

The product name is **OneRoot**. Do not rename the app, project, targets, bundle display name, documentation, or user-facing strings to Bridge or any other concept name.

---

## 1. Read this before making changes

Before editing code, read these files in this order:

1. `CLAUDE.md` - development workflow and current UX direction
2. `README.md` - the best available record of what is already implemented
3. `SPEC.md` - original architecture, technical constraints, and baseline acceptance criteria
4. the relevant source files and tests for the requested feature

Treat the documents as follows when they disagree:

- **Current code and passing tests** are the source of truth for actual behavior.
- **README.md** is the source of truth for the current implemented feature set, but verify important claims against the code because parts of the README may describe older or reverted implementations.
- **This CLAUDE.md** is the source of truth for development workflow and future UX direction.
- **SPEC.md** remains authoritative for architecture and platform constraints unless this file explicitly supersedes it.

Do not assume the repository still matches an earlier phase description. Inspect the implementation before proposing or making changes.

---

## 2. How to work with me

- I am the developer and owner. I will run OneRoot in Xcode and provide feedback.
- Work on **one coherent feature or UX phase at a time**.
- Do not scaffold the entire future roadmap in one change.
- Before coding, inspect the relevant implementation and briefly state:
  - what exists now;
  - what will change;
  - which files are expected to change;
  - any meaningful technical or UX risks.
- Keep changes small enough to review and test.
- Preserve working behavior unless the requested phase explicitly changes it.
- After each phase, provide:
  - a concise summary of what changed;
  - the files added or materially changed;
  - tests added or updated;
  - exact manual verification steps;
  - known limitations or deliberate scope decisions;
  - the recommended next phase.
- Stop after completing the requested phase and wait for my go-ahead.
- If the requested UX conflicts with AppKit, macOS behavior, file safety, accessibility, or the existing architecture, explain the tradeoff instead of silently changing direction.
- Never substitute a visually impressive mock implementation for reliable file operations.

---

## 3. Ground truth and technical constraints

### UI architecture

- **SwiftUI is the default framework for new OneRoot UX.** Use it for window composition, the global destination sidebar, tabs, toolbar, breadcrumbs, search surfaces, Inspector, contextual workspace, Workspaces, Quick Actions, Settings, onboarding, and supporting dialogs.
- **AppKit is used selectively where it already provides a clear performance or native-interaction advantage.** Preserve the existing `NSOutlineView` as the dedicated folder-hierarchy control and the existing `NSTableView` as the primary file list.
- Do not migrate a working AppKit control to SwiftUI merely for framework consistency.
- Do not introduce a new AppKit view when SwiftUI can implement the feature cleanly without losing native behavior.
- Use `NSViewRepresentable` as a narrow bridge around the specialized AppKit controls.
- The hybrid architecture is an implementation technique, not a product goal. Keep the SwiftUI/AppKit boundary deliberate, typed, and small.

### Dependencies

- **Mac app:** no third-party dependencies unless I explicitly approve one for a specific feature
- **Linux build (issue #60, approved 2026-11-01):** third-party dependencies are fine where they make the Linux app easier to write and maintain, or work better on Linux — including a Swift GTK4 binding and swift-crypto. Keep them out of the Mac app's target, and say which ones are added and why.
- Prefer system frameworks, including AppKit, SwiftUI, Foundation, QuickLookUI, UniformTypeIdentifiers, Security, NetFS, CoreServices/FSEvents, OpenDirectory, and OSLog

### Security and distribution

- App Sandbox remains OFF
- Full Disk Access remains the current access model
- Hardened Runtime remains ON
- **Releases are signed with Developer ID and notarized** (decided 2026-10-30): OneRoot is offered to other people as a direct download, outside the Mac App Store, and must install without Gatekeeper workarounds. Debug builds from Xcode may stay on development signing.
- License: GPL-3.0-only (free/open-source software — see LICENSE; changed from PolyForm Strict 2026-11-08). The "OneRoot" name and icon are reserved (TRADEMARKS.md) and are not GPL-licensed. Contributions use a DCO sign-off (no CLA), so the project cannot be relicensed without contributors' consent. Official releases come from the owner (GitHub releases, Flathub, AUR, Homebrew).
- Do not add App Store assumptions or security-scoped bookmark architecture (OneRoot stays unsandboxed with Full Disk Access)

### Shared core (Linux port, #60)

Files listed in `Package.swift` (OneRootCore) also build on Linux: Foundation alone, Apple-only code behind `#if canImport(Darwin)` or `Platform`. After changing one, run `swift test` and `Scripts/test-linux.sh`. Details: `docs/LINUX-DEV.md`.

### Architectural rules

- Continue using MVVM with a UI-agnostic service layer
- Services must not import SwiftUI or AppKit unless an existing, deliberately documented boundary requires it
- Views must not call `FileManager` directly
- Use `URL` internally instead of string paths, except at input/display boundaries
- File and network work must not block the main thread
- Mark UI-facing view models `@MainActor`
- Use typed errors for file operations and surface failures clearly
- Avoid force unwraps in filesystem, network, path, permission, and metadata code
- Load folder contents and outline children lazily
- Prefetch required `URLResourceKey` values during directory enumeration
- Preserve expansion, selection, scroll position, tab state, and navigation context where practical
- Debounce/coalesce FSEvents and other bursty filesystem notifications
- Keep files focused and use one primary type per file where reasonable

---

## 5. Product vision

Moved to `docs/UX-DIRECTION.md` (§5). Read it before work in this area.

## 6. Target UX structure and interaction requirements

Moved to `docs/UX-DIRECTION.md` (the four-region model: Destinations → Hierarchy → Contents → Context, plus per-feature requirements 6.1–6.19). Read the subsection for the area you are changing; keep the AppKit `NSOutlineView`/`NSTableView` boundary rules from §3.

## 7. Visual design direction

Moved to `docs/UX-DIRECTION.md` (§7). Read it before work in this area.

## 8. Accessibility and interaction quality

Moved to `docs/UX-DIRECTION.md` (§8). Read it before work in this area.

## 9. Performance budgets and safety expectations

Use these as engineering targets, not promises fabricated in the UI:

- opening an ordinary local folder should feel immediate;
- directory reads must occur off the main actor;
- a folder with thousands of entries must not freeze window interaction;
- switching an already-loaded tab should not trigger avoidable re-enumeration;
- rapidly changing selection must not launch uncancelled preview/metadata work that later overwrites current state;
- search, recursive size scanning, compare operations, and visualization must be cancellable;
- filesystem notifications must be coalesced;
- network and cloud latency must produce a visible loading state rather than an apparently frozen UI.

File safety has priority over visual smoothness. Never discard an error to keep an animation or optimistic UI state looking clean.

---

## 10. Testing requirements

Moved to `docs/UX-DIRECTION.md` (§10). Read it before work in this area.

## 11. Revised roadmap

Updated 2026-10-30 to match what is actually built (see README.md for the
details of each). Status: **Done**, **Partial** (what's left is listed),
or **Not started**.

### Decisions made along the way

- **The default look follows the OneRoot design mockup**: OneRoot
  Light/Dark theme (white cards on translucent material, blue folders),
  no title bar, tabs level with the window buttons. The earlier looks
  (macOS with burgundy folders, community themes) are options in
  Settings ▸ Appearance. Visible changes should track the mockup; never
  fake data it shows (versions, activity, related files, AI).
- **Dual Pane stays side by side in the file card** (toggle in the
  Context Bar, ⌘\). It is not a bottom tool — that was tried and rejected.
- **The Context Bar** is the selection-aware row under the path bar: New,
  Sort, View, Grid/List, Dual Pane, More (current folder) when nothing is
  selected; the selection's actions when something is. It replaced the
  Quick Actions card.
- The bottom tool row holds File Operations and Visualize and is hidden
  by default.
- Folder sizes are automatic only via Settings ▸ General ▸ Always
  calculate folder sizes; View ▸ Calculate Folder Sizes is a one-off.

### UX Phase 12 - Optional intelligence — Not started

Only after the deterministic UX is excellent; interpretations shown as
filters or proposals; mutations need preview and approval.

## 12. Definition of done for a UX phase

A phase is complete only when:

- the requested behavior works in the built app;
- the implementation follows existing architecture or clearly documents an approved change;
- new filesystem work remains off the main thread;
- tests cover new service/view-model logic;
- manual verification steps are provided;
- accessibility has been considered and checked;
- error, empty, loading, and permission states are handled;
- existing file operations and navigation still work;
- README.md and SPEC.md are updated where the implemented reality changed;
- no future feature is presented in documentation as already implemented.

---

## 13. Features and patterns to avoid

- Do not rewrite the application solely to adopt a different UI framework.
- Do not recreate Windows Explorer exactly.
- Do not reproduce Finder's UI merely for familiarity.
- Do not replace normal browsing with AI.
- Do not expose every power feature at all times.
- Do not add a dashboard of decorative cards to the default browsing view.
- Do not create a virtual filesystem that hides actual paths.
- Do not silently move, rename, tag, transform, or delete files.
- Do not recursively calculate folder sizes from file-list cell rendering.
- Do not fake progress, transfer speed, cloud status, file versions, or activity.
- Do not assume cloud providers expose identical metadata or capabilities.
- Do not use real user data, home folders, cloud stores, network shares, or mounted drives in unit tests.

---

## 14. For every phase

For every phase: show screenshots of the real result (light and dark
where it matters), say up front what the phase will and won't change
visually, and stop for my review before committing.
