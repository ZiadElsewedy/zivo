#!/usr/bin/env bash
# The Phase 8 FULL eval: all cases x 6 variants x 2 reps. Baseline first —
# its rep-0 replies are the frozen reference the judge compares against.
#
#   functions/eval/ask_effort/full.sh [--approve-harness]
#
# Resumable: re-running skips every (case, rep) already written.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APPROVE="${1:-}"
export EVAL_CONCURRENCY="${EVAL_CONCURRENCY:-6}"
for v in baseline v1 v2 v3 v4 v5; do
  "$HERE/eval.sh" "$v" --reps 2 $APPROVE 2>&1 | grep -E "^\[|FAILED|harness|Error" || true
  APPROVE=""
done
node "$HERE/build-report-lite.mjs" "$(cd "$HERE/../../.." && pwd)/.claude/hillclimb/ask-effort/"
echo "full eval finished — .claude/hillclimb/ask-effort/report.html"
