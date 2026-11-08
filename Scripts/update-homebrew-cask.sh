#!/bin/zsh
# Points the Homebrew cask (github.com/hillcraft-sc/homebrew-tap, Casks/oneroot.rb)
# at a published Mac release: sets the version and the DMG's sha256, commits,
# and pushes. Run after Scripts/publish-github.sh <version>.
#
#   Scripts/update-homebrew-cask.sh 2.3.2
#
# The checksum is taken from the DMG on GitHub, not the local file, so the
# cask always matches what people actually download. Needs `gh` signed in.
set -euo pipefail

TAP=hillcraft-sc/homebrew-tap
VERSION=${1:?usage: Scripts/update-homebrew-cask.sh <version>}
URL=https://github.com/hillcraft-sc/OneRoot/releases/download/v$VERSION/OneRoot-$VERSION.dmg

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▸ Downloading OneRoot-$VERSION.dmg from the release"
curl -fsSL "$URL" -o "$WORK/OneRoot.dmg"
SHA=$(shasum -a 256 "$WORK/OneRoot.dmg" | awk '{ print $1 }')

gh repo clone "$TAP" "$WORK/tap" -- --quiet
cd "$WORK/tap"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/oneroot.rb
grep -q "version \"$VERSION\"" Casks/oneroot.rb || { echo "Couldn't update Casks/oneroot.rb"; exit 1 }

# Public commits use the GitHub noreply address, not a personal email.
git config user.name "Eric Hebert"
git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
git add Casks/oneroot.rb
if git diff --cached --quiet; then echo "✓ Cask already at $VERSION"; exit 0; fi
git commit -q -m "OneRoot $VERSION"
git push -q origin HEAD:main
echo "✓ Cask updated to $VERSION ($SHA)"
