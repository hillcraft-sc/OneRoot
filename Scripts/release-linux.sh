#!/bin/zsh
# Builds the Linux release tarball (#83): a stripped binary with the Swift
# runtime linked in statically, plus the desktop entry, AppStream metadata,
# icon, LICENSE and install.sh. Built inside an OrbStack machine; the tarball's glibc
# floor is that machine's, and the app needs libadwaita 1.7+ (AdwToggleGroup, AdwWrapBox),
# so build on Debian 13 (trixie).
#
#   Scripts/release-linux.sh 0.1.0 [machine-suffix]     default: trixie
#
# Output: build/release/OneRoot-<version>-linux-<arch>.tar.gz and a .sha256.
# The arch is the machine's; for x86_64 build in an amd64 OrbStack machine
# (orb create --arch amd64 debian:trixie oneroot-trixie-x64, then pass
# trixie-x64; under emulation the default build system can't find swiftc, so
# also set SWIFT_BUILD_EXTRA='--build-system native'). Release assets: attach to the GitHub release by hand or with
# `gh release upload`; then paste the sha256 values into Linux/packaging/PKGBUILD.
set -euo pipefail
VERSION=${1:?usage: Scripts/release-linux.sh <version> [machine-suffix]}
MACHINE=oneroot-${2:-trixie}
ROOT=${0:A:h:h}
OUT=$ROOT/build/release
mkdir -p "$OUT"

ARCH=$(LC_ALL=C orb -m $MACHINE uname -m 2>/dev/null | tail -1)
NAME=OneRoot-$VERSION-linux-$ARCH
STAGE=/tmp/$NAME

echo "▸ Building in $MACHINE ($ARCH)"
LC_ALL=C orb -m $MACHINE bash -lc ". ~/.local/share/swiftly/env.sh
set -eo pipefail
cd '$ROOT/Linux'
# Never package a stale binary from an earlier build: remove it, then require a fresh one.
rm -f /tmp/oneroot-linux-release/release/OneRootLinux
swift build -c release --static-swift-stdlib ${SWIFT_BUILD_EXTRA:-} --scratch-path /tmp/oneroot-linux-release 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'error:|Build complete' || true
[ -x /tmp/oneroot-linux-release/release/OneRootLinux ] || { echo 'Build failed: no binary, nothing packaged.'; exit 1; }
rm -rf '$STAGE'; mkdir -p '$STAGE'
install -m755 /tmp/oneroot-linux-release/release/OneRootLinux '$STAGE/oneroot'
strip '$STAGE/oneroot'
cp packaging/com.hillcraft_sc.OneRoot.desktop packaging/com.hillcraft_sc.OneRoot.metainfo.xml packaging/com.hillcraft_sc.OneRoot.png '$STAGE/'
cp '$ROOT/LICENSE' '$ROOT/THIRD-PARTY-NOTICES.md' '$STAGE/'
install -m755 packaging/install.sh '$STAGE/'
cd /tmp && tar -czf '$OUT/$NAME.tar.gz' '$NAME'
" 2>&1 | grep -v setlocale

( cd "$OUT" && shasum -a 256 "$NAME.tar.gz" | tee "$NAME.tar.gz.sha256" )
echo "✓ $OUT/$NAME.tar.gz"
