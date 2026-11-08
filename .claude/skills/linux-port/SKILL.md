---
name: linux-port
description: Port one Mac OneRoot feature to the Linux GTK app (a phase L1-L10 of the Linux 1.0 plan). Use when asked to work on Linux parity, a Linux phase, or a row of Linux/PARITY.md.
---

# Porting one feature to OneRoot for Linux

Read only: `CLAUDE.md` §2/§3, `docs/LINUX-DEV.md`, the phase's rows in `Linux/PARITY.md`. Do NOT launch broad Explore agents; the parity file already says where code lives.

## Recipe (one phase at a time)

1. **State up front** (CLAUDE.md §2): what exists, what changes, files, risks, what the phase will and won't look like. Linux text on any public page stays "prototype" until the owner signs off 1.0.
2. **Reuse the shared logic.** The service/view model is usually already in the root `Package.swift` list. If it is Mac-only, port it: Observation (`@Observable`) instead of Combine, Foundation only or behind `Platform`/`#if canImport(Darwin)`, then add the file to the `Package.swift` list and its tests to the test list. Linux replacements for Apple APIs: GdkPixbuf (images), Pango+Cairo (text to PDF), libqpdf (PDF merge, approve at start of L7), GIO/GVfs (network shares), libsecret (credentials), `recently-used.xbel` (Recents).
3. **Write the GTK view** with the patterns in `docs/LINUX-DEV.md` (`AdvancedSearchWindow` for windows, `AppWindow+Files` for actions/menus/prompts, `Dialogs`, `ObservationWatch`). One primary type per file; no `FileManager` in views; no file work on the main thread; accelerators registered with the action; every control gets an accessible label and a menu/shortcut path.
4. **Tests.** Logic in the core -> package tests (macOS `swift test` + `Scripts/test-linux.sh`); display-free UI logic -> `Linux/Tests/OneRootLinuxTests`. Temp dirs only, never the real home, mounts or Trash.
5. **Verify on screen.** Add `Scripts/ui-scenarios/<feature>.txt`, run `Scripts/linux-ui-check.sh <feature>` (and `--dark`, narrow `--size 900x700`), and Read the PNGs in `build/shots/`. Check the app log lines the script prints (crashes/warnings).
6. **Regress.** `Scripts/linux-build.sh`; Xcode build of the Mac app if any shared file changed.
7. **Docs.** Update `Linux/PARITY.md` rows, `README.md`, `docs/LINUX-DEV.md` if a new gotcha appeared. Document only what is built.
8. **Report** (CLAUDE.md §2): summary, files, tests, exact manual steps for the owner's Omarchy laptop (keyboard-only flow, large folder, permission-denied path, removable drive, multiple tabs/windows), limitations, next phase. Show the screenshots. **Stop and wait for the owner's go-ahead; don't commit or publish before it.**

## Token discipline

- Read `PARITY.md` rows and the named files, not whole directories. Use `Grep` for symbols.
- Keep build/test output filtered (the scripts already do); never paste full logs.
- One phase per session; `/clear` after the owner approves.
