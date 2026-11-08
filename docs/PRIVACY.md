# Privacy

OneRoot is a file manager. It works with the files on your Mac and on the servers you connect it to, and nothing else. It has no analytics, no ads, no accounts, and no third-party code, and it never sends anything about you or your files to its developer or anyone else.

## What OneRoot connects to

OneRoot makes one network request of its own, and only if you ask for it: the **update check**. When you choose OneRoot ▸ Check for Updates…, or once a day if you turn on **Settings ▸ General ▸ Check for updates automatically** (off by default), it asks GitHub, where OneRoot's releases are published, for the latest version number and its release notes. The request carries nothing about you or your files — only what any web request does, such as your IP address, which GitHub sees under [its own privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). OneRoot never downloads or installs anything by itself.

Otherwise, OneRoot only talks to servers you ask it to:

- **Network shares** you connect to (Connect to Server, or a share already mounted on your Mac), through macOS's own file sharing.
- **SSH servers** you send files to with Copy via SSH.
- **Cloud folders** such as iCloud Drive appear as ordinary folders. Your cloud provider's own app does the syncing; OneRoot never contacts the provider.

## Full Disk Access

OneRoot asks for Full Disk Access so it can show every folder the way Finder can. It uses that access only to do what you ask: list, preview, search, copy, move, rename, and trash files. It doesn't scan, upload, or index your files in the background.

## What stays on your Mac

OneRoot keeps its settings and a few lists in its preferences on your Mac:

| What | Why |
| --- | --- |
| Settings, window layout, open tabs | To reopen where you left off |
| Pinned folders, Workspaces, recent locations | So the sidebar and Go menu remember them |
| Saved SSH destinations (host, user, folder, key file path) | To send files there again |
| Records of items OneRoot moved to the Trash | So Put Back knows where they came from |

The File Operations history and Undo are kept in memory only and are gone when you quit OneRoot.

**Passwords** for SSH destinations are kept in your macOS Keychain, never in OneRoot's preferences. Passwords for network shares are handled by macOS.

Search uses Spotlight, macOS's own index on your Mac. Quick Look previews and conversions (images, PDFs, documents) run on your Mac with macOS's own frameworks.

## Removing OneRoot

Drag OneRoot from Applications to the Trash. To remove its settings as well, delete `~/Library/Preferences/com.oneroot.OneRoot.plist`, and any OneRoot entries in Keychain Access.

## Contact

Questions about privacy? Use the email address at the bottom of this page.

*Last updated November 1, 2026.*
