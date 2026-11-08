#!/bin/zsh
# Mirrors the committed source tree (HEAD) to the public GitHub repo as ONE new
# commit on top of its history. Forgejo stays the source of truth and keeps the
# full history; GitHub only ever gets snapshots.
#
#   Scripts/publish-source.sh "message"      (default: "Source snapshot <short sha>")
#   DRY_RUN=1 Scripts/publish-source.sh      build the snapshot, don't push
#
# Only committed files go out (git archive), so untracked/ignored local files
# can't leak. Server and deploy details are left out (EXCLUDES). The GitHub
# front page is Public/README.md; the developer README ships as DEVELOPMENT.md.
# Needs `gh` signed in as the repo owner.
set -euo pipefail

REPO=hillcraft-sc/OneRoot
ROOT=${0:A:h:h}
EXCLUDES=(website/README.md website/Dockerfile website/docker-compose.yml website/nginx.conf)

cd "$ROOT"
[[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "Commit your changes first."; exit 1 }
SHA=$(git rev-parse --short HEAD)
MSG=${1:-"Source snapshot $SHA"}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▸ Cloning $REPO"
gh repo clone "$REPO" "$WORK/repo" -- --quiet
cd "$WORK/repo"
git rm -rq --ignore-unmatch . >/dev/null 2>&1 || true
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

echo "▸ Exporting HEAD ($SHA)"
git -C "$ROOT" archive HEAD | tar -x -C "$WORK/repo"
for excluded in $EXCLUDES; do rm -f "$WORK/repo/$excluded"; done
mv README.md DEVELOPMENT.md
cp Public/README.md README.md
cp Public/icon.png icon.png
rm -rf Public/notes   # release notes live on the GitHub releases themselves

# Public commits use the GitHub noreply address, not a personal email.
git config user.name "Eric Hebert"
git config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
git add -A
if git diff --cached --quiet; then echo "✓ Nothing to publish."; exit 0; fi
git commit -q -m "$MSG"
if [[ -n ${DRY_RUN:-} ]]; then rm -rf /tmp/oneroot-mirror-preview; cp -R "$WORK/repo" /tmp/oneroot-mirror-preview; echo "✓ Dry run: committed locally only; preview in /tmp/oneroot-mirror-preview"; exit 0; fi
git push -q origin HEAD:main
echo "✓ https://github.com/$REPO"
