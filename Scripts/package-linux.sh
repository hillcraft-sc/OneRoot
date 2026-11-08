#!/bin/zsh
# Builds a .deb and an .rpm from the release tarball that
# Scripts/release-linux.sh made, for Debian/Ubuntu and Fedora/openSUSE users
# who don't use Flatpak. Run it after release-linux.sh, once per architecture.
# Built inside the same OrbStack machine as the tarball (needs dpkg-deb, and
# `rpm` for rpmbuild: sudo apt install rpm).
#
#   Scripts/package-linux.sh 2.3.0 [machine-suffix]     default: trixie
#
# Output: build/release/oneroot_<version>_<arch>.deb and
#         build/release/oneroot-<version>-1.<arch>.rpm (and .sha256 files).
set -euo pipefail
VERSION=${1:?usage: Scripts/package-linux.sh <version> [machine-suffix]}
MACHINE=oneroot-${2:-trixie}
ROOT=${0:A:h:h}
OUT=$ROOT/build/release

ARCH=$(LC_ALL=C orb -m $MACHINE uname -m 2>/dev/null | tail -1)
case $ARCH in
    x86_64)  DEBARCH=amd64 ;;
    aarch64) DEBARCH=arm64 ;;
    *) echo "Unsupported architecture $ARCH"; exit 1 ;;
esac
TARBALL=$OUT/OneRoot-$VERSION-linux-$ARCH.tar.gz
[[ -f $TARBALL ]] || { echo "Missing $TARBALL (run Scripts/release-linux.sh)"; exit 1 }
DEB=oneroot_${VERSION}_$DEBARCH.deb
RPM=oneroot-$VERSION-1.$ARCH.rpm

LC_ALL=C orb -m $MACHINE bash -s <<REMOTE 2>&1 | { grep -v setlocale || true; }
set -euo pipefail
command -v rpmbuild >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rpm >/dev/null
W=\$(mktemp -d); trap 'rm -rf "\$W"' EXIT
tar xzf '$TARBALL' -C "\$W"
SRC=\$W/OneRoot-$VERSION-linux-$ARCH
ID=com.hillcraft_sc.OneRoot

# --- .deb ---
D=\$W/deb
install -Dm755 "\$SRC/oneroot" "\$D/usr/bin/oneroot"
install -Dm644 "\$SRC/\$ID.desktop" "\$D/usr/share/applications/\$ID.desktop"
install -Dm644 "\$SRC/\$ID.metainfo.xml" "\$D/usr/share/metainfo/\$ID.metainfo.xml"
install -Dm644 "\$SRC/\$ID.png" "\$D/usr/share/icons/hicolor/256x256/apps/\$ID.png"
install -Dm644 "\$SRC/LICENSE" "\$D/usr/share/doc/oneroot/copyright"
install -Dm644 "\$SRC/THIRD-PARTY-NOTICES.md" "\$D/usr/share/doc/oneroot/THIRD-PARTY-NOTICES.md"
mkdir -p "\$D/DEBIAN"
cat > "\$D/DEBIAN/control" <<CTL
Package: oneroot
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEBARCH
Maintainer: Eric Hebert <eric@hillcraft.email>
Homepage: https://oneroot.hillcraft-sc.com
Depends: libgtk-4-1, libadwaita-1-0 (>= 1.7), libgtksourceview-5-0, libxml2, libcurl4t64 | libcurl4, libarchive-tools, libqpdf30 | libqpdf29t64 | libqpdf29, libsecret-1-0, libpoppler-glib8t64 | libpoppler-glib8
Recommends: gvfs, gvfs-backends, gvfs-fuse, openssh-client
Description: A fast, native file manager with tabs, dual pane and a folder tree
 OneRoot keeps browsing calm and familiar, with the power tools one click
 away: tabs that remember where you were, an Inspector, Dual Pane, search,
 and file operations you can undo. Licensed under the GNU GPL v3
 (see /usr/share/doc/oneroot/copyright).
CTL
dpkg-deb --root-owner-group --build "\$D" '$OUT/$DEB' >/dev/null

# --- .rpm ---
R=\$W/rpm
mkdir -p "\$R"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cat > "\$R/SPECS/oneroot.spec" <<SPEC
Name: oneroot
Version: $VERSION
Release: 1
Summary: A fast, native file manager with tabs, dual pane and a folder tree
License: GPL-3.0-only
URL: https://oneroot.hillcraft-sc.com
Requires: libadwaita >= 1.7, gtk4, gtksourceview5, libxml2, libcurl, bsdtar, qpdf-libs, libsecret, poppler-glib
AutoReqProv: no
%global debug_package %{nil}
%global __strip /bin/true

%description
OneRoot keeps browsing calm and familiar, with the power tools one click
away: tabs that remember where you were, an Inspector, Dual Pane, search,
and file operations you can undo. Free software under the GNU GPL v3.

%install
install -Dm755 "\$SRC/oneroot" %{buildroot}/usr/bin/oneroot
install -Dm644 "\$SRC/\$ID.desktop" %{buildroot}/usr/share/applications/\$ID.desktop
install -Dm644 "\$SRC/\$ID.metainfo.xml" %{buildroot}/usr/share/metainfo/\$ID.metainfo.xml
install -Dm644 "\$SRC/\$ID.png" %{buildroot}/usr/share/icons/hicolor/256x256/apps/\$ID.png
install -Dm644 "\$SRC/LICENSE" %{buildroot}/usr/share/licenses/oneroot/LICENSE
install -Dm644 "\$SRC/THIRD-PARTY-NOTICES.md" %{buildroot}/usr/share/licenses/oneroot/THIRD-PARTY-NOTICES.md

%files
/usr/bin/oneroot
/usr/share/applications/\$ID.desktop
/usr/share/metainfo/\$ID.metainfo.xml
/usr/share/icons/hicolor/256x256/apps/\$ID.png
%license /usr/share/licenses/oneroot/LICENSE
%license /usr/share/licenses/oneroot/THIRD-PARTY-NOTICES.md
SPEC
rpmbuild -bb --target $ARCH --define "_topdir \$R" "\$R/SPECS/oneroot.spec" >/dev/null 2>&1 || rpmbuild -bb --target $ARCH --define "_topdir \$R" "\$R/SPECS/oneroot.spec" 2>&1 | tail -15
cp "\$R"/RPMS/$ARCH/*.rpm '$OUT/$RPM'
REMOTE

cd "$OUT"
for f in "$DEB" "$RPM"; do shasum -a 256 "$f" | tee "$f.sha256"; done
echo "✓ $OUT/$DEB, $OUT/$RPM"
