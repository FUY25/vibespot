#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_PATH="$ROOT_DIR/Casks/vibespot.rb"
VERSION_INPUT="${1:-}"
DMG_PATH="${2:-$ROOT_DIR/dist/VibeSpot.dmg}"

if [[ -z "$VERSION_INPUT" ]]; then
  echo "Usage: $0 <version-or-v-prefixed-tag> [path-to-dmg]" >&2
  exit 1
fi

VERSION="${VERSION_INPUT#v}"

if [[ -z "$VERSION" || "$VERSION" == *[[:space:]]* || "$VERSION" == v* ]]; then
  echo "Invalid version: $VERSION_INPUT" >&2
  echo "Expected a release version like 0.1.0 or v0.1.0." >&2
  exit 1
fi

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask file missing: $CASK_PATH" >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG file missing: $DMG_PATH" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

perl -0pi -e "s/version \"[^\"]+\"/version \"$VERSION\"/; s/sha256 \"[0-9a-f]{64}\"/sha256 \"$SHA256\"/" "$CASK_PATH"

if ! grep -q "version \"$VERSION\"" "$CASK_PATH"; then
  echo "Failed to update cask version in $CASK_PATH" >&2
  exit 1
fi

if ! grep -q "sha256 \"$SHA256\"" "$CASK_PATH"; then
  echo "Failed to update cask sha256 in $CASK_PATH" >&2
  exit 1
fi

echo "Updated $CASK_PATH"
echo "version=$VERSION"
echo "sha256=$SHA256"
