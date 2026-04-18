#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Optional one-shot cleanup to remove stale debug/release artifacts.
if [[ "${1:-}" == "--clean" ]]; then
  swift package clean
  shift
fi

# Optional one-shot onboarding reset for QA.
if [[ "${1:-}" == "--reset-onboarding" ]]; then
  for domain in "com.fuyuming.Flare" "Flare"; do
    defaults delete "$domain" "flare.settings.v1" >/dev/null 2>&1 || true
    defaults delete "$domain" "flare.onboardingCompleted" >/dev/null 2>&1 || true
  done
  shift
fi

exec swift run -c debug Flare "$@"
