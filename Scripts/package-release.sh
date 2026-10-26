#!/bin/bash
# Builds a release SimpleAudio.app bundle, packages it as build/SimpleAudio-<version>.zip,
# computes its SHA-256 digest, and prints a ready-to-publish SimpleUpdater JSON manifest snippet.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/bundle.sh release

APP="build/SimpleAudio.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ZIP="build/SimpleAudio-${VERSION}.zip"

rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat <<EOF

=== Release Archive Ready ===
Archive : $ZIP
Version : $VERSION (build $BUILD)
SHA-256 : $SHA256

--- JSON Manifest Snippet ---
{
  "net.cieadrienm.simpleaudio": {
    "version": "$VERSION",
    "build": $BUILD,
    "url": "https://github.com/cieadrienm/SimpleAudio/releases/download/v${VERSION}/SimpleAudio-${VERSION}.zip",
    "sha256": "$SHA256",
    "notes_fr": "Mise à jour de SimpleAudio v${VERSION}.",
    "notes_en": "SimpleAudio v${VERSION} update."
  }
}
EOF
