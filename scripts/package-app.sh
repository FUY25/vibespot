#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-VibeSpot}"
BUNDLE_ID="${BUNDLE_ID:-com.fuyuming.vibespot}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
INFO_TEMPLATE="$ROOT_DIR/packaging/VibeSpot-Info.plist.template"
ICON_PATH="$ROOT_DIR/packaging/AppIcon.icns"

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$ICON_PATH" ]]; then
  "$ROOT_DIR/scripts/export-app-icon.sh" >/dev/null
fi

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/Flare"
RESOURCE_BUNDLE_PATH="$BIN_DIR/Flare_Flare.bundle"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Built executable missing: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "SwiftPM resource bundle missing: $RESOURCE_BUNDLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE/Contents/Resources/Flare_Flare.bundle"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

sed \
  -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__BUILD__|$BUILD|g" \
  "$INFO_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"

ln -s "Contents/Resources/Flare_Flare.bundle" "$APP_BUNDLE/Flare_Flare.bundle"

echo "Packaged $APP_BUNDLE"
