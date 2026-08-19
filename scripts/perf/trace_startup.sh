#!/usr/bin/env bash
# M7 Pass 1 — cold-start trace. Runs a PROFILE build with --trace-startup on a
# physical device, then copies the resulting build/start_up_info.json into
# docs/performance/traces/ with a timestamp so it's easy to send back.
#
# Usage:
#   scripts/perf/trace_startup.sh <device-id> [label]
#
# Find <device-id> with:  flutter devices
# `label` is an optional tag for the filename (e.g. cold, warm1). Default: run.
#
# After the app reaches the home screen, press `q` in the flutter console to
# quit — Flutter writes build/start_up_info.json on exit and this script copies
# it out. Run it 3× (once right after install = cold, then twice warm).
set -euo pipefail

DEVICE="${1:-}"
LABEL="${2:-run}"

if [[ -z "$DEVICE" ]]; then
  echo "usage: scripts/perf/trace_startup.sh <device-id> [label]" >&2
  echo "hint:  run 'flutter devices' to get <device-id> (must be a PHYSICAL device)" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/performance/traces"
mkdir -p "$OUT_DIR"

echo "▶ Profile build with --trace-startup on device: $DEVICE"
echo "  Config: Profile (config/profile.json) — the M7 configuration."
echo "  Let the app reach the home screen, then press 'q' to quit."
echo

# --trace-startup writes build/start_up_info.json once startup completes.
# The profile config keeps App Check on real attestation (production-like).
flutter run --profile --trace-startup \
  --dart-define-from-file=config/profile.json \
  -d "$DEVICE"

SRC="$REPO_ROOT/build/start_up_info.json"
if [[ -f "$SRC" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  DEST="$OUT_DIR/start_up_info-${LABEL}-${STAMP}.json"
  cp "$SRC" "$DEST"
  echo
  echo "✔ Saved startup trace → ${DEST#"$REPO_ROOT"/}"
  echo "  Headline fields: timeToFirstFrameMicros, timeToFrameworkInitMicros"
else
  echo "✘ build/start_up_info.json not found — did startup finish before you quit?" >&2
  exit 1
fi
