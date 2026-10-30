#!/bin/zsh
# Builds the Mac app signed with a Developer ID, packs it in a DMG, signs,
# notarises and staples the DMG, and checks it with Gatekeeper.
#
#   NMW_TEAM=<team id> NMW_NOTARY_PROFILE=<notarytool keychain profile> apple/scripts/release-mac.sh
#
# Output: apple/build/release/Notes-my-Way-<version>.dmg
# The notary profile is made once with `xcrun notarytool store-credentials`.
set -euo pipefail

: "${NMW_TEAM:?set NMW_TEAM to the Apple developer team ID}"
: "${NMW_NOTARY_PROFILE:?set NMW_NOTARY_PROFILE to a notarytool keychain profile}"
# The team's Developer ID Application certificate, by hash (unambiguous with several teams).
IDENTITY=$(security find-identity -v -p codesigning \
  | awk -v t="($NMW_TEAM)" '/Developer ID Application/ && index($0, t) { print $2; exit }')
: "${IDENTITY:?no Developer ID Application certificate for team $NMW_TEAM in the keychain}"

cd "$(dirname "$0")/.."
OUT=build/release
DD=$(mktemp -d /tmp/nmw-release-XXXXXX)
trap 'rm -rf "$DD"' EXIT
mkdir -p "$OUT"

xcodegen generate -q
VERSION=$(xcodebuild -project nmw.xcodeproj -scheme nmw -showBuildSettings -destination 'platform=macOS' 2>/dev/null \
  | awk '/ MARKETING_VERSION =/ { print $3; exit }')
echo "Notes my Way $VERSION"

# Release build, signed inside out by Xcode (extensions first), hardened
# runtime and a secure timestamp, as notarisation requires.
xcodebuild build -project nmw.xcodeproj -scheme nmw -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$NMW_TEAM" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet
APP="$DD/Build/Products/Release/Notes my Way.app"

codesign --verify --strict --deep "$APP"
# A plain build adds get-task-allow (debugging), which notarisation refuses.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "get-task-allow is still in the entitlements" >&2; exit 1
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier"

# The DMG: the app and a link to /Applications.
STAGE="$DD/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Notes my Way.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Notes-my-Way-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Notes my Way $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --force --timestamp -s "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NMW_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG"
echo "$DMG"
