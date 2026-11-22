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
# Build number = commit count: always increases, which is what Sparkle compares (CFBundleVersion).
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Sparkle.framework (updates). Glisse is not sandboxed, so Sparkle's XPC services are not needed.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(swift build -c release --show-bin-path)/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

# Inside out: Sparkle's helpers, the framework, then the app.
# Hardened runtime + secure timestamp: required for notarization.
FLAGS=(--force --sign "$SIGN_ID")
[[ "$SIGN_ID" != "-" ]] && FLAGS+=(--options runtime --timestamp)
for target in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW" "$APP"; do
  codesign "${FLAGS[@]}" "$target"
done
codesign --verify --strict "$APP"
echo "✓ $PWD/$APP (signed with: $SIGN_ID)"
