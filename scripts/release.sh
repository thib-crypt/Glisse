#!/bin/zsh
# Builds a signed, notarized DMG and (optionally) publishes it as a GitHub Release.
#
#   scripts/release.sh              → dist/Glisse-<version>.dmg, signed + notarized + stapled
#   scripts/release.sh --publish    → same, then tags v<version> and creates the GitHub Release
#   NOTARIZE=0 scripts/release.sh   → skip notarization (local test only; Gatekeeper will block it elsewhere)
#
# One-time setup (stores an app-specific password in the Keychain):
#   xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id PG46BWSK3T
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
set -euo pipefail
cd "${0:A:h}/.."

APP=Glisse
SIGN_ID="${SIGN_ID:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
PUBLISH=0; [[ "${1:-}" == "--publish" ]] && PUBLISH=1

if (( PUBLISH )); then
  [[ -z "$(git status --porcelain)" ]] || { echo "✗ Uncommitted changes: commit before publishing." >&2; exit 1; }
fi

echo "→ Building $APP (Release)…"
SIGN_ID="$SIGN_ID" scripts/build.sh
BUILT="build/$APP.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILT/Contents/Info.plist")

echo "→ Packaging $APP $VERSION…"
mkdir -p dist
DMG="dist/$APP-$VERSION.dmg"
STAGE=$(mktemp -d)
ditto "$BUILT" "$STAGE/$APP.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
rm -rf "$STAGE"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

if [[ "${NOTARIZE:-1}" != "0" ]]; then
  echo "→ Notarizing (profile « $NOTARY_PROFILE »)…"
  LOG=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) || true
  print -r -- "$LOG"
  grep -q "status: Accepted" <<<"$LOG" || { echo "✗ Notarization failed (xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE)." >&2; exit 1; }
  xcrun stapler staple -q "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "✓ $DMG"
echo "  sha256 $SHA"

if (( PUBLISH )); then
  TAG="v$VERSION"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "✗ Tag $TAG already exists: bump CFBundleShortVersionString in Resources/Info.plist." >&2; exit 1; }
  git tag -a "$TAG" -m "$APP $VERSION"
  git push origin "$TAG"
  gh release create "$TAG" "$DMG" --verify-tag --title "$APP $VERSION" --generate-notes
  echo "✓ Published $TAG"
fi
