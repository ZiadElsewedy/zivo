#!/usr/bin/env bash
# Runs the Phase 8 reasoning-policy eval for one variant inside a throwaway
# Firestore emulator (port 8187, project demo-zivo-eval — never prod).
#
#   functions/eval/ask_effort/eval.sh <variant> [runner args…]
#   EVAL_CASES=id1,id2 functions/eval/ask_effort/eval.sh v1      # a subset
#
# The Anthropic key is read from the project's Secret Manager for this run
# only; it is never written to disk.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VARIANT="$1"; shift
cd "$ROOT"
if [ "${EVAL_DRY:-}" != "1" ]; then
  ANTHROPIC_API_KEY="$(firebase functions:secrets:access ANTHROPIC_API_KEY --project zivo-63f15)"
  export ANTHROPIC_API_KEY
fi
FLOW="${EVAL_FLOW:-.claude/hillclimb/ask-effort}"
firebase emulators:exec --config "$HERE/firebase.eval.json" --only firestore \
  --project demo-zivo-eval \
  "node functions/eval/ask_effort/run.mjs --flow $FLOW --variant $VARIANT --concurrency ${EVAL_CONCURRENCY:-4} --timeout-s 240 $*"
