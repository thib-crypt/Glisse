#!/bin/zsh
# Builds build/Glisse.app with SwiftPM and signs it.
#   scripts/build.sh            → signed with your Developer ID certificate (ad hoc if none is installed)
#   SIGN_ID=- scripts/build.sh  → ad hoc signature
# For a distributable, notarized DMG use scripts/release.sh.
set -euo pipefail
cd "${0:A:h}/.."

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')}"
SIGN_ID="${SIGN_ID:--}"

swift build -c release
APP=build/Glisse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Glisse "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  # Hardened runtime + secure timestamp: required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ $PWD/$APP (signed with: $SIGN_ID)"
