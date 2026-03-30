#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Optional one-shot cleanup to remove stale debug/release artifacts.
if [[ "${1:-}" == "--clean" ]]; then
  swift package clean
  shift
fi

exec swift run -c debug VibeLight "$@"
