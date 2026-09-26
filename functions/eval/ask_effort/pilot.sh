#!/usr/bin/env bash
# The Phase 8 PAID PILOT: 8 cases (one per kind of turn) x 6 variants, 1 rep.
# Baseline runs first — its replies become the frozen reference the judge
# compares every other variant against.
#
#   functions/eval/ask_effort/pilot.sh [--approve-harness]
#
# --approve-harness records the runner's sha after you've reviewed it (needed
# once, and again whenever the runner changes); it is passed to the first
# variant only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export EVAL_CASES="real-greet-ar,probe-diet-left,real-skip-today,probe-log-2-eggs,var-spend-week-ar,probe-training-progress,probe-900kcal,real-no-ful"
APPROVE="${1:-}"
for v in baseline v1 v2 v3 v4 v5; do
  "$HERE/eval.sh" "$v" $APPROVE 2>&1 | grep -E "^\[|FAILED|harness|Error" || true
  APPROVE=""
done
echo "pilot finished — results in .claude/hillclimb/ask-effort/"
