#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

staging_dir="$(mktemp -d "$PWD/build/.dmg.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
payload="$staging_dir/payload"
app="$payload/MeimeiNotes.app"
mkdir "$payload"
ditto "build/Meimei Notes.app" "$app"
ln -s /Applications "$payload/Applications"
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(xcrun lipo -archs "$app/Contents/MacOS/MeimeiNotes")"
name="MeimeiNotes-$version-macOS-$architecture.dmg"
layout="$staging_dir/layout.dmg"
image="$staging_dir/$name"

hdiutil makehybrid -quiet -hfs -hfs-volume-name MeimeiNotes -o "$layout" "$payload"
hdiutil convert "$layout" -quiet -format UDZO -o "$image"
hdiutil verify -quiet "$image"

mv -f "$image" "build/$name"
printf 'Built %s\n' "$PWD/build/$name"
