# Glisse

A menu-bar timer you set with one gesture: press the icon, **drag down**, release. The further you pull, the longer the
timer — a thread follows the cursor from the icon with a live bubble showing the duration.

**Requires** macOS 14 or later. UI in French.

## Install
Download the latest `Glisse-<version>.dmg` from [Releases](https://github.com/thib-crypt/Glisse/releases), open it and drag
Glisse to Applications. The app is signed with a Developer ID and notarized by Apple.
Allow notifications on first launch to be alerted when a timer ends.

## Features
- **Drag to set**: non-linear curve, precise for short durations and fast for long ones
  (~10 pt → 1 min · 100 pt → 26 min · 200 pt → 1 h 10 · 400 pt → 3 h · 700 pt → 7 h); the color slides from turquoise
  (short) to magenta (long).
- **Quick label**: a small field appears under the icon right after a timer is created.
- **Several timers at once**, listed with their countdowns in the menu.
- **Notifications** when a timer ends.
- **Frugal**: no polling — a single one-shot wake-up is scheduled for the next visible change; no timer, no wake-up.
- Works with the macOS 26 system-rendered menu bar (reads the hardware mouse state while dragging).

## Build
Requirements: Xcode 16+ / Swift 5.10 (SwiftPM, no Xcode project).
```
scripts/build.sh               # build/Glisse.app, signed with your Developer ID (ad hoc if none)
SIGN_ID=- scripts/build.sh     # ad hoc signature
swift scripts/make_icon.swift Resources && iconutil -c icns Resources/AppIcon.iconset && rm -r Resources/AppIcon.iconset   # regenerate the icon
```

## Release
```
scripts/release.sh            # dist/Glisse-<version>.dmg — hardened runtime, signed, notarized, stapled
scripts/release.sh --publish  # + tag v<version> and GitHub Release with the DMG
```
The version is `CFBundleShortVersionString` in `Resources/Info.plist`. Notarization uses the Keychain profile `notary`
(`xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id PG46BWSK3T`, once).

## License
[MIT](LICENSE)
