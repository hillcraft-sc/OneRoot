<p align="center"><img src="icon.png" width="128" alt="OneRoot icon"></p>

<h1 align="center">OneRoot</h1>

<p align="center">A fast, native file manager for macOS, built for real file work. (A Linux prototype is available too.)</p>

<p align="center"><a href="https://github.com/hillcraft-sc/OneRoot/releases/latest"><b>Download the latest release</b></a> · <a href="https://oneroot.hillcraft-sc.com">Website</a> · <a href="https://oneroot.hillcraft-sc.com/support.html">Support</a></p>

---

OneRoot keeps browsing calm and familiar, and puts the power tools one click
away when you need them:

- **Tabs** that remember where you were, and **multiple windows**
- A **folder tree** rooted where you're working, next to a sortable,
  customizable **file list**
- **Breadcrumbs** you can click, or type a path straight into
- An **Inspector** with a large preview, details, permissions, and tags
- **Cut, copy, paste**, with progress, Cancel, and **Undo**
- **Dual Pane**: two folders side by side, F5/F6 to copy or move between
  them, and **Compare Panes** to see what differs and copy one way
- **Merge folders**, one question for many name conflicts, and Replace that
  goes to the Trash so it can be undone
- **Verify copies** byte for byte, and **Find Duplicates** to free space
- **Workspaces**: one place for a project's folders, wherever they live
- **Search** that filters the current folder or searches everything, with
  name, kind, date, size, tag, and content filters
- **Quick Actions**: resize and convert images, combine into PDF, convert
  documents, batch rename, compress and extract
- **Visualize** what's using your storage
- Network shares, external drives, iCloud Drive and other cloud folders
- Light and dark themes, and a searchable built-in Help

## Install on macOS

1. Download `OneRoot-x.y.z.dmg` from [Releases](https://github.com/hillcraft-sc/OneRoot/releases/latest).
2. Open it and drag **OneRoot** onto the **Applications** folder.
3. Open OneRoot. macOS asks once whether to open an app downloaded from the
   internet: click **Open**.

Or, with [Homebrew](https://brew.sh):

```
brew install --cask hillcraft-sc/tap/oneroot
```

and update later with `brew upgrade --cask oneroot`. If Homebrew asks you to trust the tap, run `brew trust hillcraft-sc/tap` first.

OneRoot is signed with Developer ID and notarized by Apple.

On first launch OneRoot shows you how to give it **Full Disk Access**, which it
needs to browse all your files the way Finder can. You only do this once;
updates keep the permission.

**Requires** macOS 14 Sonoma or later, on Apple silicon or Intel.

## OneRoot for Linux (early release)

**OneRoot for Linux 0.2.0 is an early release, still a prototype.** It has most of what the Mac version does (Dual Pane, Quick Actions, Workspaces, Visualize, themes, Settings), but expect rough edges, and no Mac-only features such as iCloud or Touch ID. The builds for x86_64 and aarch64 are on their own pre-release, [OneRoot for Linux 0.2.0](https://github.com/hillcraft-sc/OneRoot/releases/tag/linux-v0.2.0), with `.deb`, `.rpm` and tarball downloads, install steps, and the full list of what works and what doesn't.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/hillcraft-sc/OneRoot/issues), or email admin@hillcraft-sc.com. Help with installing and setup is on the [Support page](https://oneroot.hillcraft-sc.com/support.html).

## License

OneRoot is free software under the [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.html).
The source is in this repository (a snapshot published with each release).
The "OneRoot" name and icon are **not** covered by the GPL and may not be used
for modified versions: see [TRADEMARKS.md](TRADEMARKS.md). Contributing:
[CONTRIBUTING.md](CONTRIBUTING.md) (DCO sign-off). Building from source and
the developer notes: [DEVELOPMENT.md](DEVELOPMENT.md). Security reports:
[SECURITY.md](SECURITY.md).

© 2026 Eric Hebert.
