#!/bin/zsh
# Publishes the Linux builds to the public GitHub repo as their own
# pre-release (tag linux-v<version>), separate from the Mac releases so the
# Mac "latest" download is unaffected.
#
#   Scripts/publish-linux-github.sh 0.1.0
#
# Needs: `gh` signed in as the repo owner; the output of
# Scripts/release-linux.sh and Scripts/package-linux.sh for both
# architectures in build/release; notes in Public/notes/linux-<version>.md.
set -euo pipefail

REPO=hillcraft-sc/OneRoot
VERSION=${1:?usage: Scripts/publish-linux-github.sh <version>}
ROOT=${0:A:h:h}
OUT=$ROOT/build/release
NOTES=$ROOT/Public/notes/linux-$VERSION.md
TAG=linux-v$VERSION
FILES=( $OUT/OneRoot-$VERSION-linux-{x86_64,aarch64}.tar.gz $OUT/oneroot_${VERSION}_{amd64,arm64}.deb $OUT/oneroot-$VERSION-1.{x86_64,aarch64}.rpm )
[[ -f $NOTES ]] || { echo "Missing $NOTES"; exit 1 }
for f in $FILES; do [[ -f $f && -f $f.sha256 ]] || { echo "Missing $f or its .sha256"; exit 1 }; done
FILES+=( ${^FILES}.sha256 )

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "▸ Updating $TAG"
    gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES" --prerelease --latest=false >/dev/null
    gh release upload "$TAG" "${FILES[@]}" --repo "$REPO" --clobber
else
    echo "▸ Publishing $TAG (pre-release)"
    gh release create "$TAG" "${FILES[@]}" --repo "$REPO" --title "OneRoot for Linux $VERSION (prototype)" \
        --notes-file "$NOTES" --prerelease --latest=false
fi
echo "✓ https://github.com/$REPO/releases/tag/$TAG"
