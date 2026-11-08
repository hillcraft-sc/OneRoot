# Support

## Install

### macOS

1. Download the latest `OneRoot-x.y.z.dmg` from the Download link on the home page.
2. Open it and drag **OneRoot** onto the **Applications** folder beside it.
3. Open OneRoot from Applications. macOS asks once whether to open an app downloaded from the internet: click **Open**.

OneRoot is signed with Developer ID and notarized by Apple, so there's nothing else to approve. It needs macOS 14 Sonoma or later, on Apple silicon or Intel.

### Linux (early prototype)

OneRoot for Linux 0.2.0 is an early release with most of the Mac version's features, still rough in places. Downloads, install steps and the list of what works are on its [release page](https://github.com/hillcraft-sc/OneRoot/releases/tag/linux-v0.2.0). It needs GTK 4, libadwaita 1.7 or later and GtkSourceView 5 (Debian 13, Ubuntu 25.04, Fedora 42, Arch and newer). The Full Disk Access steps below are for macOS only.

## Give OneRoot Full Disk Access

OneRoot needs Full Disk Access to show every folder the way Finder can. On first launch it shows a button that opens the right place in System Settings:

1. In **System Settings > Privacy & Security > Full Disk Access**, turn on **OneRoot**. If it isn't listed, click **+** and choose OneRoot in Applications.
2. Quit and reopen OneRoot.

You only do this once. Updates are signed the same way, so they keep the permission.

## Update

Download the new DMG and drag OneRoot to Applications again, replacing the old copy. Your settings, tabs, pinned folders and Workspaces stay as they were.

## Learn your way around

Choose **Help > OneRoot Help** in OneRoot for a searchable guide to everything: the sidebar, tabs, the path bar, the Inspector, file operations and Undo, Dual Pane, Workspaces, search, Quick Actions, Visualize, themes and keyboard shortcuts. Many windows have a **?** button that opens the matching topic.

## Common questions

### A folder shows as empty, or says I don't have permission

OneRoot probably doesn't have Full Disk Access yet, or was given it before an update from an unsigned build. Turn it on as above; if OneRoot is already listed, remove it with **–**, add it again with **+**, and reopen OneRoot.

### Open in Terminal does nothing

The first time, macOS asks whether OneRoot may control Terminal: click **OK**. If you clicked Don't Allow, turn it on in **System Settings > Privacy & Security > Automation > OneRoot**. To use another terminal app, choose it in **OneRoot > Settings > Terminal**.

### Can I make OneRoot open instead of Finder?

Not entirely: macOS always keeps Finder running for the desktop and the Dock. You can keep OneRoot in the Dock and use it for all your file work.

## Uninstall

Drag OneRoot from Applications to the Trash. To remove its settings too, delete `~/Library/Preferences/com.oneroot.OneRoot.plist`.

## Report a problem or suggest an idea

Open an issue on [GitHub](https://github.com/hillcraft-sc/OneRoot/issues). It helps to include your macOS version (Apple menu > About This Mac), the OneRoot version (OneRoot > About OneRoot), and what you were doing when it happened.
