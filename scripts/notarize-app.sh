#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeSpot.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${2:-}}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/dist/VibeSpot.zip}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Usage: NOTARY_PROFILE='<xcrun notarytool keychain profile>' $0 [app-bundle]" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"

echo "Notarized and stapled $APP_BUNDLE"
