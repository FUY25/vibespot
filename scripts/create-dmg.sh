#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeSpot.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/VibeSpot.dmg}"
APP_NAME="$(basename "$APP_BUNDLE" .app)"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "$ROOT_DIR/dist/.dmg-staging.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"
