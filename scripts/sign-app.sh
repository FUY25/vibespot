#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/VibeSpot.app}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${2:-}}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Usage: SIGNING_IDENTITY='Developer ID Application: ...' $0 [app-bundle]" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Resources/Flare_Flare.bundle"
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/MacOS/VibeSpot"
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Signed $APP_BUNDLE"
