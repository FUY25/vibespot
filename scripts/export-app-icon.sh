#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_PATH="${1:-$ROOT_DIR/Sources/VibeLight/Resources/Branding/vibespot-mark.svg}"
OUTPUT_ICNS="${2:-$ROOT_DIR/packaging/AppIcon.icns}"

if [[ ! -f "$SVG_PATH" ]]; then
  echo "SVG not found: $SVG_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG_PATH" >/dev/null 2>&1
BASE_PNG="$TMP_DIR/$(basename "$SVG_PATH").png"

if [[ ! -f "$BASE_PNG" ]]; then
  echo "Failed to render icon preview from $SVG_PATH" >&2
  exit 1
fi

render_size() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/$name" >/dev/null 2>&1
}

render_size 16 icon_16x16.png
render_size 32 icon_16x16@2x.png
render_size 32 icon_32x32.png
render_size 64 icon_32x32@2x.png
render_size 128 icon_128x128.png
render_size 256 icon_128x128@2x.png
render_size 256 icon_256x256.png
render_size 512 icon_256x256@2x.png
render_size 512 icon_512x512.png
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "Exported app icon to $OUTPUT_ICNS"
