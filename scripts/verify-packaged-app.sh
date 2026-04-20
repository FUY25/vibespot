#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeSpot.app}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

echo "Bundle: $APP_BUNDLE"
echo "Identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
echo "Display name: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_BUNDLE/Contents/Info.plist")"
echo "Executable: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist")"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
echo "Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"

test -x "$APP_BUNDLE/Contents/MacOS/VibeSpot"
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -d "$APP_BUNDLE/Contents/Resources/Flare_Flare.bundle"
test -L "$APP_BUNDLE/Flare_Flare.bundle"

codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Packaged app structure looks valid."
