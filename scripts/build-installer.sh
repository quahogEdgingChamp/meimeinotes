#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

staging_dir="$(mktemp -d "$PWD/build/.installer.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

payload="$staging_dir/payload"
app="$payload/MeimeiNotes.app"
mkdir "$payload"
ditto "build/Meimei Notes.app" "$app"

info="$app/Contents/Info.plist"
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
architecture="$(xcrun lipo -archs "$app/Contents/MacOS/MeimeiNotes")"
package_id="$identifier.pkg"
component="MeimeiNotesComponent.pkg"
installer_name="Install MeimeiNotes.pkg"

pkgbuild --root "$payload" --component-plist App/InstallerComponents.plist \
    --install-location /Applications --identifier "$package_id" --version "$version" \
    "$staging_dir/$component"

cat > "$staging_dir/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>MeimeiNotes</title>
    <conclusion file="Conclusion.html" mime-type="text/html"/>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <options customize="never" require-scripts="false" hostArchitectures="$architecture"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="$minimum_os"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="meimeinotes"/>
    </choices-outline>
    <choice id="meimeinotes" title="MeimeiNotes" visible="false">
        <pkg-ref id="$package_id"/>
    </choice>
    <pkg-ref id="$package_id" version="$version">$component</pkg-ref>
</installer-gui-script>
EOF

productbuild --distribution "$staging_dir/Distribution.xml" --package-path "$staging_dir" \
    --resources App/InstallerResources "$staging_dir/$installer_name"
mv -f "$staging_dir/$installer_name" "build/$installer_name"
printf 'Built %s\n' "$PWD/build/$installer_name"
