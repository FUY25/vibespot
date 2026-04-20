#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_PATH="${1:-$ROOT_DIR/dist/VibeSpot.dmg}"
APP_NAME="${APP_NAME:-VibeSpot}"
VERIFY_ROOT="${VERIFY_ROOT:-$(mktemp -d "$ROOT_DIR/dist/.beta-verify.XXXXXX")}"
MOUNT_POINT="$VERIFY_ROOT/mount"
INSTALL_ROOT="$VERIFY_ROOT/install-root"
INSTALL_APP_DIR="$INSTALL_ROOT/Applications"
LOG_PATH="$VERIFY_ROOT/launch.log"
PID_FILE="$VERIFY_ROOT/pid"
ATTACHED_DMG=0
OPEN_LOG_PATH="$VERIFY_ROOT/open.log"

find_running_pid_for_executable() {
  local executable_path="$1"
  /bin/ps -axo pid=,args= | /usr/bin/awk -v target="$executable_path" '
    index($0, target) {
      print $1
    }
  ' | /usr/bin/head -n 1
}

cleanup() {
  if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" >/dev/null 2>&1; then
      kill "$PID" >/dev/null 2>&1 || true
      wait "$PID" >/dev/null 2>&1 || true
    fi
  fi
  if [[ "$ATTACHED_DMG" == "1" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "$INSTALL_APP_DIR"

if [[ "$ARTIFACT_PATH" == *.dmg ]]; then
  mkdir -p "$MOUNT_POINT"
  hdiutil attach "$ARTIFACT_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet
  ATTACHED_DMG=1
  APP_SOURCE="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
else
  APP_SOURCE="$ARTIFACT_PATH"
fi

if [[ -z "${APP_SOURCE:-}" || ! -d "$APP_SOURCE" ]]; then
  echo "Could not locate app bundle inside artifact: $ARTIFACT_PATH" >&2
  exit 1
fi

APP_COPY="$INSTALL_APP_DIR/$(basename "$APP_SOURCE")"
ditto "$APP_SOURCE" "$APP_COPY"

echo "Installed beta copy to: $APP_COPY"
echo
echo "Gatekeeper assessment before override:"
spctl --assess --type execute -vv "$APP_COPY" || true

echo
echo "Clearing quarantine on the temp install copy to simulate Privacy & Security > Open Anyway."
xattr -r -d com.apple.quarantine "$APP_COPY" 2>/dev/null || true

EXECUTABLE_PATH="$APP_COPY/Contents/MacOS/$APP_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Executable missing: $EXECUTABLE_PATH" >&2
  exit 1
fi

BEFORE_PID="$(find_running_pid_for_executable "$EXECUTABLE_PATH" || true)"
open -n "$APP_COPY" >"$OPEN_LOG_PATH" 2>&1

for _ in {1..20}; do
  APP_PID="$(find_running_pid_for_executable "$EXECUTABLE_PATH" || true)"
  if [[ -n "$APP_PID" && "$APP_PID" != "$BEFORE_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "$APP_PID" > "$PID_FILE"
    echo "First-launch smoke passed. PID=$APP_PID"
    echo "Open command log: $OPEN_LOG_PATH"
    exit 0
  fi
  sleep 0.5
done

echo "Packaged app exited before the smoke window elapsed." >&2
if [[ -f "$OPEN_LOG_PATH" ]]; then
  cat "$OPEN_LOG_PATH" >&2
fi
exit 1
