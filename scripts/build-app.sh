#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

module_cache="$PWD/.build/app-module-cache"
mkdir -p build "$module_cache"
staging_dir="$(mktemp -d "$PWD/build/.bundle.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

app_name="Meimei Notes.app"
bundle="$staging_dir/$app_name"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' App/Info.plist)"
xcrun --sdk macosx swiftc \
    -target "$(uname -m)-apple-macosx$minimum_os" \
    -module-name MeimeiNotes -swift-version 5 -parse-as-library \
    -O -whole-module-optimization -module-cache-path "$module_cache" \
    Sources/MeimeiNotes/*.swift -o "$bundle/Contents/MacOS/MeimeiNotes"

cp App/Info.plist "$bundle/Contents/"
cp App/Resources/* "$bundle/Contents/Resources/"
codesign --force --sign - "$bundle"

destination="$PWD/build/$app_name"
if [[ -e "$destination" ]]; then
    mv "$destination" "$staging_dir/previous.app"
fi
if ! mv "$bundle" "$destination"; then
    if [[ -e "$staging_dir/previous.app" ]]; then
        mv "$staging_dir/previous.app" "$destination"
    fi
    exit 1
fi
printf 'Built %s\n' "$destination"

