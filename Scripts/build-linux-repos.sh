#!/bin/zsh
# Builds a signed apt repository (reprepro) and a signed dnf/yum repository
# (createrepo_c) from the .deb and .rpm files in build/release, as plain static
# files you can serve from any web server or GitHub Pages. Publishes nothing.
#
#   Scripts/build-linux-repos.sh <version> <gpg-key-id> [gnupg-home]
#
# Runs in the OrbStack machine (default oneroot-trixie; override with
# ONEROOT_REPO_MACHINE=) because reprepro and createrepo_c are Linux tools:
#   sudo apt install reprepro createrepo-c gnupg
# The signing key must be in <gnupg-home> as seen from that machine (default
# ~/.gnupg there). Use a dedicated key for the repository, not your personal one.
#
# Output: build/repos/{apt,rpm}/ and build/repos/oneroot-archive-keyring.gpg
# (binary, for apt) and oneroot-archive-keyring.asc (armored, for rpm), plus
# build/repos/INSTALL.txt with the lines users run.
set -euo pipefail
VERSION=${1:?usage: Scripts/build-linux-repos.sh <version> <gpg-key-id> [gnupg-home]}
KEY=${2:?usage: Scripts/build-linux-repos.sh <version> <gpg-key-id> [gnupg-home]}
GNUPGHOME_ARG=${3:-}
MACHINE=oneroot-${ONEROOT_REPO_MACHINE:-trixie}
ROOT=${0:A:h:h}
REL=$ROOT/build/release
OUT=$ROOT/build/repos
mkdir -p "$OUT"

LC_ALL=C orb -m $MACHINE bash -s -- "$VERSION" "$KEY" "$GNUPGHOME_ARG" "$REL" "$OUT" <<'REMOTE' 2>&1 | { grep -v setlocale || true; }
set -euo pipefail
VERSION=$1; KEY=$2; GH=$3; REL=$4; OUT=$5
[ -n "$GH" ] && export GNUPGHOME=$GH
for tool in reprepro createrepo_c gpg; do
    command -v $tool >/dev/null || { echo "Missing $tool: sudo apt install reprepro createrepo-c gnupg"; exit 1; }
done
gpg --list-secret-keys "$KEY" >/dev/null 2>&1 || { echo "No secret key $KEY in ${GNUPGHOME:-~/.gnupg}"; exit 1; }
ls "$REL"/oneroot_${VERSION}_amd64.deb "$REL"/oneroot_${VERSION}_arm64.deb \
   "$REL"/oneroot-$VERSION-1.x86_64.rpm "$REL"/oneroot-$VERSION-1.aarch64.rpm >/dev/null

# --- apt (one "stable" suite, component "main"; the package carries its own libadwaita >= 1.7 dependency)
APT=$OUT/apt; STATE=$OUT/apt-state   # STATE (conf + db) stays with you; APT is what you serve
rm -rf "$APT" "$STATE"; mkdir -p "$APT" "$STATE/conf"
cat > "$STATE/conf/distributions" <<CONF
Origin: OneRoot
Label: OneRoot
Codename: stable
Architectures: amd64 arm64
Components: main
Description: OneRoot for Linux
SignWith: $KEY
CONF
for deb in "$REL"/oneroot_${VERSION}_*.deb; do reprepro -b "$STATE" --outdir "$APT" includedeb stable "$deb" >/dev/null; done

# --- dnf
RPM=$OUT/rpm
rm -rf "$RPM"; mkdir -p "$RPM/x86_64" "$RPM/aarch64"
cp "$REL"/oneroot-$VERSION-1.x86_64.rpm "$RPM/x86_64/"
cp "$REL"/oneroot-$VERSION-1.aarch64.rpm "$RPM/aarch64/"
for arch in x86_64 aarch64; do
    createrepo_c -q "$RPM/$arch"
    gpg --batch --yes --armor --detach-sign -u "$KEY" -o "$RPM/$arch/repodata/repomd.xml.asc" "$RPM/$arch/repodata/repomd.xml"
done

# --- public key
gpg --export "$KEY" > "$OUT/oneroot-archive-keyring.gpg"
gpg --armor --export "$KEY" > "$OUT/oneroot-archive-keyring.asc"
cat > "$OUT/INSTALL.txt" <<TXT
Replace https://REPO.EXAMPLE with where you serve build/repos from.

Debian / Ubuntu 25.04+:
  sudo install -D -m644 oneroot-archive-keyring.gpg /etc/apt/keyrings/oneroot.gpg
  echo "deb [signed-by=/etc/apt/keyrings/oneroot.gpg] https://REPO.EXAMPLE/apt stable main" | sudo tee /etc/apt/sources.list.d/oneroot.list
  sudo apt update && sudo apt install oneroot

Fedora:
  sudo tee /etc/yum.repos.d/oneroot.repo <<EOF
  [oneroot]
  name=OneRoot
  baseurl=https://REPO.EXAMPLE/rpm/\\\$basearch
  enabled=1
  gpgcheck=0
  repo_gpgcheck=1
  gpgkey=https://REPO.EXAMPLE/oneroot-archive-keyring.asc
  EOF
  sudo dnf install oneroot
(The rpm files themselves aren't signed, so gpgcheck=0; repo_gpgcheck=1 verifies the repository metadata.)
TXT
echo "✓ repositories built for $VERSION"
REMOTE
echo "Serve $OUT/apt, $OUT/rpm and the two keyring files; keep $OUT/apt-state for the next release. Nothing was published."
