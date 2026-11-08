#!/bin/zsh
# Publishes a release built by Scripts/release.sh to the public GitHub repo:
# a source snapshot (Scripts/publish-source.sh) plus the release itself.
# Forgejo stays the source of truth.
#
#   Scripts/publish-github.sh 2.2.0
#
# Needs: `gh` signed in as the repo owner, build/release/OneRoot-<version>.dmg,
# and release notes in Public/notes/<version>.md. The Linux builds are published
# separately by Scripts/publish-linux-github.sh.
set -euo pipefail

REPO=hillcraft-sc/OneRoot
VERSION=${1:?usage: Scripts/publish-github.sh <version>}
ROOT=${0:A:h:h}
DMG=$ROOT/build/release/OneRoot-$VERSION.dmg
NOTES=$ROOT/Public/notes/$VERSION.md
[[ -f $DMG ]] || { echo "Missing $DMG (run Scripts/release.sh)"; exit 1 }
[[ -f $NOTES ]] || { echo "Missing $NOTES"; exit 1 }
xcrun stapler validate -q "$DMG" || { echo "$DMG isn't notarized and stapled"; exit 1 }

"$ROOT/Scripts/publish-source.sh" "Update for OneRoot $VERSION"

# Run again for a published version to update its README and notes only.
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "▸ Updating the notes of v$VERSION"
    gh release edit "v$VERSION" --repo "$REPO" --notes-file "$NOTES" >/dev/null
else
    echo "▸ Publishing v$VERSION"
    gh release create "v$VERSION" "$DMG" \
        --repo "$REPO" --title "OneRoot $VERSION" --notes-file "$NOTES"
fi
echo "✓ https://github.com/$REPO/releases/tag/v$VERSION"
