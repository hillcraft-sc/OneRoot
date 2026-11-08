# Linux development guide

Read this instead of re-exploring the repo. Status of every feature is in `Linux/PARITY.md`; the plan is `~/.claude/plans/` (Linux 1.0, phases L0–L10).

## Layout

- `Package.swift` (root): **OneRootCore**, the shared Swift files, module name `OneRoot`, built with `-enable-testing`. The Xcode app compiles the same files. Every file in its list must build with Foundation alone; Apple-only code goes behind `#if canImport(Darwin)` / `os(macOS)` or through `Platform` (`Services/MacPlatform.swift`, `Services/LinuxPlatform.swift`, same members).
- `Linux/`: the GTK 4 / libadwaita app (`OneRootLinux`, binding `makoni/swift-adwaita`, pinned) and `Linux/Tests/OneRootLinuxTests` (display-free UI logic). Sources are in `Linux/Sources/OneRootLinux/`; `@testable import OneRoot` reaches core internals.
- `Linux/packaging/`: desktop entry, metainfo, PKGBUILD, Flatpak manifest, `install.sh`.

## Machines (OrbStack; `orb list`)

| Machine | Use |
|---|---|
| `oneroot-trixie` (Debian 13, arm64) | the build/UI machine; default for every script |
| `oneroot-trixie-x64` (amd64, emulated) | x86_64 release builds only |
| `oneroot-arch`, `-fedora`, `-ubuntu` (24.04), `-debian` (12) | core tests / package install tests; Ubuntu 24.04 and Debian 12 can't run the GUI (libadwaita < 1.7) |

## Commands

| Task | Command |
|---|---|
| Build the GTK app + run UI-logic tests | `Scripts/linux-build.sh [machine-suffix] [--no-test]` |
| Headless screenshots | `Scripts/linux-ui-check.sh <scenario> [--dark] [--size WxH]` → `build/shots/` (scenarios in `Scripts/ui-scenarios/*.txt`) |
| Core tests on distros | `Scripts/test-linux.sh` (and `swift test` on the Mac) |
| Tarball / packages / publish | `Scripts/release-linux.sh <ver> [suffix]`, `Scripts/package-linux.sh`, `Scripts/publish-linux-github.sh` |

Any change to a shared file also needs an Xcode build of the Mac app.

## Headless harness

`linux-ui-check.sh` runs the debug binary under Xvfb (`:77`) with `HOME` pointed at a throwaway fixture (`/tmp/oneroot-ui-home`: Documents, Pictures, Downloads with 400 files, Projects, a PNG, text, a tar.gz), software rendering, no window manager, no portal. It never touches the real home. Scenario commands: `shot`, `key`, `type`, `click`, `dblclick`, `sleep`, `cd`, `size`, `sh`, and `env` before launch (see the script header). Copies finish in about a second on these machines, so to hold one open set `env ONEROOT_TEST_COPY_DELAY_MS=1` (test-only slowdown in `LinuxFileCopier`, off by default; progress is still real). A folder of 20,000 small files makes a good slow copy; `Scripts/ui-scenarios/operations*.txt` show it, with Pause/Cancel/failure/Verify; `settings*.txt` and `themes.txt` drive the Settings dialog (it is a modal dialog, so scenario clicks use its tab bar at the top). Add a scenario file per feature; read the PNGs with the Read tool. `ONEROOT_TRACE=1` adds trace output to the log; the script prints the app's warnings and whether it crashed.

## Gotchas already paid for

- Arch needs `libxml2-legacy` (the binary links `libxml2.so.2`) and `libncurses`.
- The binary needs libadwaita ≥ 1.7 (`AdwToggleGroup`, `AdwWrapBox`) and GtkSourceView 5. Test packages on a clean machine, not one with dev packages.
- amd64 emulation: swiftly crashes (install the toolchain tarball), `bwrap` doesn't work (no flatpak-builder), and `swift build` needs `SWIFT_BUILD_EXTRA='--build-system native'`.
- flatpak-builder wants its state dir on the same filesystem as the build dir: run it from `/tmp`.
- The OrbStack machines mount the Mac's home, so Linux builds can write into the repo; use `--scratch-path /tmp/...` (the scripts do).
- Linux name sorting uses GLib's `g_utf8_collate_key_for_filename`; tags are `user.xdg.tags`; Trash follows freedesktop.org.

- **`UserDefaults` on Linux is memory-only until `synchronize()`** (it then writes `$HOME/.config/<program>.plist`). `OneRootApp` saves every 2 s and at quit; before L2 nothing did, so settings and the window layout were lost at exit. Use `--keep-home` on the harness to check that a choice survives a restart (`theme-pick`, then `theme-check`).
- Known open item: during a long copy with the File Operations panel open, GTK sometimes logs `Trying to measure GtkPaned … for height of 54, but it needs at least 88`. Only a warning; the layout looks right. Not traced (L9 didn't reproduce it).
- **Narrow windows (L9):** all three Paneds (`outer`, `hierarchy`, `inspector`) have shrinkable children so the window's minimum is the header bar (~470 px), not the sum of the panes. With only some children shrinkable GTK logs `Trying to measure GtkPaned … for width of 360, but it needs at least 361` whenever the file list shows its empty page. `AppWindow+Layout` re-fits the layout once per frame when the window width changes (`default-width` isn't notified on WM resizes). In the harness `--size` is the *screen*; use the scenario `size W H` command to resize the window (`narrow.txt`); `hidpi.txt` needs `--size 2800x1800`.
- The app starts in the machine's real home folder (it ignores `$HOME`), so scenarios `cd` into the fixture explicitly.
- Linux Foundation lacks `DateComponentsFormatter`; `FileOperationText` has a Linux path (`abbreviatedDuration`, `spokenDuration`). Check for other Apple-only Foundation types when adding a Views/ file to the core list.

- A `SignalListItemFactory` must be kept by the owner (`FileListPane.gridFactory`): the Swift wrapper holds the setup/bind closures, and a factory that is only handed to GTK crashes in libgtk as soon as it binds.
- `FileListPane` shows List (ColumnView) or Grid (GridView) over one `MultiSelection`; both hand their cells to `addRightClick`/`addDragAndDrop`.
- Help text is written with `**bold**` and `` `code` `` and turned into Pango markup by `HelpMarkup`; shortcut keys are shown as plain text (a backtick key would otherwise toggle code).

- **qpdf, Cairo and Pango (L7, approved for the Linux app only):** `Linux/Package.swift` has two system-library targets, `CQPDF` (`libqpdf-dev`, the C API plus the in-process `qpdfjob_run_from_argv` used for the merge) and `CPangoCairoPDF` (`libpango1.0-dev`). On the build machines: `sudo apt-get install libqpdf-dev libpango1.0-dev`. Runtime: `libqpdf30` / `libqpdf29t64`, `qpdf` (Arch), `qpdf-libs` (Fedora).
- **poppler-glib (approved for the Linux app only, 2026-11-07):** `Linux/Package.swift` has a `CPopplerGLib` system-library target (`libpoppler-glib-dev` / `poppler-glib-devel`); `PDFPagePreview` draws page 1 for the Inspector and Quick Look. Runtime: `libpoppler-glib8t64` (Debian/Ubuntu), `poppler-glib` (Fedora, Arch). Added to the .deb/.rpm/PKGBUILD dependencies. The Flatpak manifest does not bundle it yet (nor qpdf).
- **Live SSH test:** `OneRootTests/SSHCopyLiveTests` is skipped unless `ONEROOT_TEST_SSH_PORT`, `ONEROOT_TEST_SSH_KEY` and `ONEROOT_TEST_SSH_DIR` are set. It needs a throwaway machine: `apt install openssh-server`, run `/usr/sbin/sshd -f <cfg>` on 127.0.0.1:2222 (own HostKey and AuthorizedKeysFile, `UsePAM no`, `StrictModes no`), and remove `[127.0.0.1]:2222` from `~/.ssh/known_hosts` before and after (the test trusts the key). scp only draws its progress meter on a terminal that it runs in the foreground of, so `SSHCopyService` runs it under `/usr/bin/script -q -e -f -c` when a progress handler is given.
- **Quick Actions seam:** the shared Runner, Planner, Catalog and sheet model use `QuickActionServices.current` (protocols in `Models/QuickAction.swift`). The Mac app builds its own through `QuickActionServices.mac()` (guarded by `#if os(macOS) && !SWIFT_PACKAGE`, so the package never references Mac-only files); the Linux app installs `OneRootApp.quickActionServices` in `installPlatformHooks()`. Package tests of core code that needs services must inject them.
- GdkPixbuf types import into Swift as `OpaquePointer`, not `UnsafeMutablePointer<GdkPixbuf>`.

- **libsecret, GIO and the L8 test rig (approved for the Linux app only):** `Linux/Package.swift` has a `CLibSecret` system-library target (`libsecret-1-dev`; runtime `libsecret-1-0` / `libsecret` / `libsecret` on Arch). Its `shim.h` wraps the varargs API in four plain-C `static inline` helpers (Swift can't call varargs). `KeyringService` uses it; `KeyringServiceTests` only touch the real keyring with `ONEROOT_TEST_KEYRING=1` inside `dbus-run-session -- sh -c 'echo x | gnome-keyring-daemon --unlock --components=secrets; …'`. Network mounts use GIO directly (`NetworkMounter`: `GMountOperation` + `g_file_mount_enclosing_volume`; no `gio` CLI, whose prompts are stdout-buffered when piped).
- **Headless rig for SSH and Samba** (in `oneroot-trixie`; not part of the repo): `apt install openssh-server samba gvfs-backends`, a user `sshtest` (password `pw12345`) with `PasswordAuthentication yes`, `ssh-keyscan -H localhost >> ~/.ssh/known_hosts`; Samba user `smbtest` (`secret1`) with a share `[oneroottest]` at `/srv/oneroot-smb`. Scenarios `ssh-copy`, `connect-server`, `connect-server-wrong`. **Don't install gnome-keyring in that machine**: the harness has a display, gcr-prompter opens a "create keyring" window nobody can see, and every GVfs mount waits on it forever (it looks like a hang in OneRoot). The container has no FUSE, so a mounted share connects but "can't be browsed".
- **Recents** read `recently-used.xbel` (`RecentlyUsedIndex`, core, `XMLParser` via `FoundationXML` on Linux). The app ignores `$HOME` but not `$XDG_DATA_HOME`, which the harness sets; `Platform.recentsRoots` is `/` on Linux (the xbel is the user's own list) and the home folder on the Mac.
- **Updates (L10):** the in-app check exists only for tarball installs (`InstallMethod`: `share/oneroot/install-method` next to the binary's prefix, or `ONEROOT_INSTALL_METHOD=tarball` for the harness). `UpdateChecker.Channel` keeps `linux-v*` tags away from the Mac and the reverse; after the first stable Linux release the Mac's old `/releases/latest` lookup would have seen it. Repo scripts need `reprepro createrepo-c gnupg` in the build machine; test with a throwaway `GNUPGHOME` in `/tmp` and an `http.server`, never the real key.
- **Sessions:** `SessionKeeper` (Linux) over the shared `SessionService`/`SavedSession`; `WindowViewModel(restoring:)` does the rebuilding. A `Paned` in a tab that isn't showing has width 0: don't set its position then (it collapsed the first pane).

## GTK patterns (copy these)

- Main loop: `MainQueueBridge` + `CMainQueue` let GLib run Swift's main queue. Short GTK delays: `MainContext.task {}` / `MainContext.delay(ms:)`.
- Binding view models: `ObservationWatch.watch({ tracked reads }) { new in … }`; keep the returned watches on the owner. See `AppWindow.swift`, `FileListPane.swift`, `TabContent.swift`.
- Window actions: `SimpleAction(name:)` + `window.addAction` + `app.application.setAccelerators([...], for: "win.name")` (`AppWindow.addActions`, `AppWindow+Files.addFileActions`). Main menu: `AppWindow.makeMainMenuButton` (`GMenuRef`). Context menu: `AppWindow+Files.showContextMenu`.
- Dialogs: `Dialogs.alert/promptName/resolveConflicts`; synchronous questions from the core via `Dialogs.runModal`; hooks wired in `OneRootApp.installPlatformHooks()`.
- Secondary window: copy `AdvancedSearchWindow.swift` (one instance on `OneRootApp`, `onClose`, handoff through a `…HandoffCenter`).
- Settings: `SettingsDialog.swift` is an `AdwPreferencesDialog` (pages of `PreferencesGroup`s with `SwitchRow`/`ComboRow`/`EntryRow`/`ActionRow`); rows read and write the shared services/`UserDefaults` keys directly. Themes: shared `ThemeStore` + `ThemeController` (libadwaita color scheme + a CSS provider from `ThemeCSS`).
- Bottom panel: `OperationsPanel.swift` (rows updated in place from `FileOperationProgressCenter`; `toolbar.addBottomBar`); app-wide announcements and the quit guard live in `OneRootApp`.
- Prompts raised by view models: `AppWindow.watchPrompts(of:)`.
- Errors: `pane.errorMessage` → toast; modal errors via `Dialogs.showError`; inline pane states for loading / permission denied.
