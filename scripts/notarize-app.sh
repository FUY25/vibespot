#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${1:-$ROOT_DIR/dist/VibeSpot.dmg}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${2:-}}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/dist/VibeSpot.zip}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Usage: NOTARY_PROFILE='<xcrun notarytool keychain profile>' $0 [app-bundle-or-archive]" >&2
  exit 1
fi

if [[ ! -e "$INPUT_PATH" ]]; then
  echo "Artifact not found: $INPUT_PATH" >&2
  exit 1
fi

SUBMISSION_PATH="$INPUT_PATH"
if [[ -d "$INPUT_PATH" ]]; then
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$INPUT_PATH" "$ZIP_PATH"
  SUBMISSION_PATH="$ZIP_PATH"
fi

xcrun notarytool submit "$SUBMISSION_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$INPUT_PATH"

echo "Notarized and stapled $INPUT_PATH"
