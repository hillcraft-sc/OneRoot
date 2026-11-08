#!/bin/zsh
# Builds a signed, notarized, stapled OneRoot-<version>.dmg in build/release.
#
#   Scripts/release.sh
#
# Needs, once per Mac:
#   - a "Developer ID Application" certificate for team 6S92GA582Q
#     (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates)
#   - notarization credentials saved as the "OneRoot" keychain profile:
#     xcrun notarytool store-credentials OneRoot --apple-id <id> --team-id 6S92GA582Q
set -euo pipefail

TEAM=6S92GA582Q
PROFILE=OneRoot
ROOT=${0:A:h:h}
OUT=$ROOT/build/release
WORK=$(mktemp -d)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Forget the build's scratch copies too, or System Settings may show one of
# them (and its icon) for OneRoot instead of the installed app.
cleanup() {
    for app in "$WORK"/**/OneRoot.app(N/); do "$LSREGISTER" -u "$app" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
VERSION=$(xcodebuild -project OneRoot.xcodeproj -scheme OneRoot -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION =/ { print $2; exit }')
DMG=$OUT/OneRoot-$VERSION.dmg
mkdir -p "$OUT"
[[ -e $DMG ]] && { echo "$DMG already exists"; exit 1 }

if [[ ${SKIP_BENCHMARK:-0} != 1 ]]; then
    "$ROOT/Scripts/benchmark.sh"
fi

echo "▸ Archiving OneRoot $VERSION"
xcodebuild -project OneRoot.xcodeproj -scheme OneRoot -configuration Release \
    -destination generic/platform=macOS -archivePath "$WORK/OneRoot.xcarchive" -derivedDataPath "$WORK/dd" \
    archive -quiet

echo "▸ Exporting with Developer ID"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$WORK/OneRoot.xcarchive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" -quiet
APP=$WORK/export/OneRoot.app
codesign --verify --deep --strict "$APP"

echo "▸ Making the disk image"
mkdir "$WORK/dmg"
ditto "$APP" "$WORK/dmg/OneRoot.app"
ln -s /Applications "$WORK/dmg/Applications"
cp "$ROOT/LICENSE" "$WORK/dmg/LICENSE.txt"
hdiutil create -volname "OneRoot $VERSION" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -quiet "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Checking Gatekeeper"
spctl --assess --type open --context context:primary-signature -v "$DMG"
MOUNT=$(hdiutil attach "$DMG" -nobrowse -readonly | awk -F'\t' '/\/Volumes\// { print $NF }')
spctl --assess --type execute -v "$MOUNT/OneRoot.app"
"$LSREGISTER" -u "$MOUNT/OneRoot.app" 2>/dev/null || true
hdiutil detach "$MOUNT" -quiet

echo "✓ $DMG"
