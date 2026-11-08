#!/bin/zsh
# Builds everything for a Linux release, locally, and publishes nothing:
# tarball, .deb and .rpm for aarch64 and x86_64, plus one SHA256SUMS file.
#
#   Scripts/release-linux-all.sh 1.0.0
#
# Needs the OrbStack machines oneroot-trixie (arm64) and oneroot-trixie-x64
# (amd64, emulated; slow). Then, by hand and only when you decide to:
#   Scripts/build-linux-repos.sh 1.0.0 <gpg-key-id>      apt + dnf repositories
#   Scripts/publish-linux-github.sh 1.0.0                 the GitHub release
# and update the sha256 values in Linux/packaging/PKGBUILD and the Flatpak manifest.
set -euo pipefail
VERSION=${1:?usage: Scripts/release-linux-all.sh <version>}
ROOT=${0:A:h:h}
OUT=$ROOT/build/release
cd "$ROOT"

for machine in trixie trixie-x64; do
    extra=''
    [[ $machine == trixie-x64 ]] && extra='--build-system native'
    echo "━━ $machine"
    SWIFT_BUILD_EXTRA=$extra Scripts/release-linux.sh "$VERSION" $machine
    Scripts/package-linux.sh "$VERSION" $machine
done

cd "$OUT"
rm -f SHA256SUMS
files=(OneRoot-$VERSION-linux-*.tar.gz oneroot_${VERSION}_*.deb oneroot-$VERSION-1.*.rpm)
(( ${#files} == 6 )) || { echo "Expected 6 artifacts, found ${#files}: $files"; exit 1 }
shasum -a 256 $files > SHA256SUMS
cat SHA256SUMS
echo "✓ $OUT (nothing was published)"
