#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_PATH="$ROOT_DIR/Casks/vibespot.rb"
TAP_NAME="${HOMEBREW_VERIFY_TAP:-vibespot/local}"
TMP_TAP="$(mktemp -d /tmp/vibespot-homebrew-tap.XXXXXX)"

cleanup() {
  HOMEBREW_NO_AUTO_UPDATE=1 brew untap "$TAP_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP_TAP"
}
trap cleanup EXIT

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask file missing: $CASK_PATH" >&2
  exit 1
fi

ruby -c "$CASK_PATH" >/dev/null

mkdir -p "$TMP_TAP/Casks"
cp "$CASK_PATH" "$TMP_TAP/Casks/vibespot.rb"

git -C "$TMP_TAP" init -q
git -C "$TMP_TAP" config user.email "vibespot-homebrew-verify@example.invalid"
git -C "$TMP_TAP" config user.name "VibeSpot Homebrew Verify"
git -C "$TMP_TAP" add Casks/vibespot.rb
git -C "$TMP_TAP" commit -q -m "Add VibeSpot cask"

HOMEBREW_NO_AUTO_UPDATE=1 brew untap "$TAP_NAME" >/dev/null 2>&1 || true
HOMEBREW_NO_AUTO_UPDATE=1 brew tap "$TAP_NAME" "$TMP_TAP"
HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask "$TAP_NAME/vibespot"
HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask --dry-run "$TAP_NAME/vibespot"

echo "Homebrew cask verification passed for $TAP_NAME/vibespot"
