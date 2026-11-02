#!/bin/sh
# Adds the strings the code uses to the string catalogs in Localization/
# (Localizable, AppShortcuts), so new ones show up untranslated in Xcode's
# catalog editor. Builds for macOS and iOS, since some views are per platform.
# The editor engine keeps its own catalog (../markdownkit, MarkdownEngineCore/Resources).
set -eu
cd "$(dirname "$0")/.."
dd=/tmp/nmw-strings-dd
for destination in 'platform=macOS' 'generic/platform=iOS Simulator'; do
    xcodebuild build -project nmw.xcodeproj -scheme nmw -configuration Debug -destination "$destination" \
        -derivedDataPath "$dd" SWIFT_EMIT_LOC_STRINGS=YES CODE_SIGNING_ALLOWED=NO -quiet
done
set --
for file in $(find "$dd/Build/Intermediates.noindex" -name '*.stringsdata' | grep -E '/(nmw|NmwShare|NmwWidgets|NmwUI-t|NmwCore-t|NmwShared-t)\.build/'); do
    set -- "$@" --stringsdata "$file"
done
xcrun xcstringstool sync Localization/Localizable.xcstrings Localization/AppShortcuts.xcstrings "$@"
rm -rf "$dd"
# Strings still waiting for a Polish translation.
/usr/bin/python3 - <<'PY'
import glob, json
for path in sorted(glob.glob("Localization/*.xcstrings")):
    strings = json.load(open(path))["strings"]
    todo = [k for k, v in strings.items() if v.get("shouldTranslate", True) and "pl" not in v.get("localizations", {})]
    for key in todo:
        print(f"{path}: no Polish for {key!r}")
PY
echo "Updated Localization/*.xcstrings"
