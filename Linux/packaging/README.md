# Linux packaging (#83)

| File | Status |
|---|---|
| `com.hillcraft_sc.OneRoot.desktop`, `.metainfo.xml`, `.png` | Done; validated with `desktop-file-validate` and `appstreamcli` |
| `install.sh` (in the tarball) | Done; user or `--system` install and `--uninstall`, tested on Debian 13 |
| `Scripts/package-linux.sh` | Done; builds `.deb` and `.rpm` from the tarball; tested on Debian 13, Ubuntu 24.04 (correctly refuses: libadwaita 1.5) and Fedora 44 |
| `Scripts/release-linux.sh` | Done; builds `OneRoot-<ver>-linux-<arch>.tar.gz` (static Swift runtime, stripped) |
| `PKGBUILD` (`oneroot-bin`) | Built with makepkg on Arch (aarch64) against the linux-v0.2.0 pre-release; `.SRCINFO` generated; **not yet pushed to the AUR** |
| `com.hillcraft_sc.OneRoot.yml` (Flatpak) | Built, installed and launched with flatpak-builder on aarch64 (GNOME 51 runtime; every library resolves; appstreamcli passes). **x86_64 not built here** (bwrap doesn't run under amd64 emulation) and **not submitted to Flathub**; Flathub builds each arch itself, and may ask for a from-source build instead of repackaging the tarball |

Requirements of the binary: libadwaita 1.7+ (Debian 13, Ubuntu 25.04, Fedora 42, Arch), GTK 4, GtkSourceView 5, libxml2 and libcurl;
`bsdtar` (libarchive) for Compress/Extract. Debian 12 is too old (libadwaita 1.2).

**Repositories and release (L10).** `Scripts/release-linux-all.sh <ver>` builds everything for both architectures and writes `SHA256SUMS`; `Scripts/build-linux-repos.sh <ver> <gpg-key-id> [gnupg-home]` builds the signed apt and dnf repositories as static files in `build/repos/` (with `INSTALL.txt`). Neither publishes anything. Package installs carry no `install-method` marker, so they hide the in-app update check; `install.sh` writes it.

Not done: an AppImage (GTK 4 + libadwaita + GtkSourceView and their data would all have to be bundled, which the Flatpak already does better) and Flathub submission (a pull request to flathub/flathub from a GitHub account, then manual review).
