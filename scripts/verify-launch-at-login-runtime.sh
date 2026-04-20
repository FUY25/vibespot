#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeSpot.app}"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/VibeSpot"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Executable missing: $EXECUTABLE" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
echo "Bundle: $APP_BUNDLE"
echo "Identifier: $BUNDLE_ID"

STATUS="$("$EXECUTABLE" --print-launch-at-login-support | tr -d '[:space:]')"
if [[ "$STATUS" != "supported" ]]; then
  echo "Packaged app does not consider launch-at-login supported." >&2
  exit 1
fi

echo "Packaged app reports launch-at-login runtime support."
