#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

release=false
installer_name="Install MeimeiNotes.pkg"
if [[ "$#" -eq 1 && "${1:-}" == "--release" ]]; then
    release=true
    : "${MEIMEINOTES_APP_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
    : "${MEIMEINOTES_INSTALLER_SIGN_IDENTITY:?Set the Developer ID Installer signing identity}"
    : "${MEIMEINOTES_NOTARY_PROFILE:?Set a notarytool Keychain profile name}"
    set -- --sign "$MEIMEINOTES_INSTALLER_SIGN_IDENTITY"
    installer_name="Install MeimeiNotes (Release).pkg"
elif [[ "$#" -ne 0 ]]; then
    printf 'Usage: %s [--release]\n' "$0" >&2
    exit 2
fi

./scripts/build-app.sh

staging_dir="$(mktemp -d "$PWD/build/app.noindex/.installer.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

payload="$staging_dir/payload"
app="$payload/MeimeiNotes.app"
mkdir "$payload"
ditto "build/app.noindex/Meimei Notes.app" "$app"

info="$app/Contents/Info.plist"
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
architecture="$(xcrun lipo -archs "$app/Contents/MacOS/MeimeiNotes")"
package_id="$identifier.pkg"
component="MeimeiNotesComponent.pkg"

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

package="$staging_dir/$installer_name"
productbuild --distribution "$staging_dir/Distribution.xml" --package-path "$staging_dir" \
    --resources App/InstallerResources "$@" "$package"

if "$release"; then
    result="$staging_dir/notary-result.json"
    if ! xcrun notarytool submit "$package" --keychain-profile "$MEIMEINOTES_NOTARY_PROFILE" \
            --wait --output-format json > "$result" \
            || [[ "$(plutil -extract status raw -o - "$result")" != "Accepted" ]]; then
        cat "$result" >&2
        exit 1
    fi
    xcrun stapler staple "$package"
    xcrun stapler validate "$package"
fi

mv -f "$package" "build/$installer_name"
printf 'Built %s\n' "$PWD/build/$installer_name"
