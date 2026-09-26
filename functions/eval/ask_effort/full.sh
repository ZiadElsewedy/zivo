#!/usr/bin/env bash
# The Phase 8 FULL eval: all cases x 6 variants x 2 reps. Baseline first —
# its rep-0 replies are the frozen reference the judge compares against.
#
#   functions/eval/ask_effort/full.sh [--approve-harness]
#
# Resumable: re-running skips every (case, rep) already written.
set -uo pipefail
# PAID-CALL LOCK (owner, 2026-09-26): no paid run without their explicit
# approval — see assertPaidRunApproved in run.mjs.
if [ "${EVAL_DRY:-}" != "1" ] && [ "${ZIVO_EVAL_PAID_APPROVED:-}" != "yes-i-approve-paid-api-calls" ]; then
  echo "REFUSING: paid Anthropic eval runs are closed (owner, 2026-09-26). Needs the owner's explicit approval." >&2
  exit 3
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
APPROVE="${1:-}"
export EVAL_CONCURRENCY="${EVAL_CONCURRENCY:-6}"
for v in baseline v1 v2 v3 v4 v5; do
  "$HERE/eval.sh" "$v" --reps 2 $APPROVE 2>&1 | grep -E "^\[|FAILED|harness|Error" || true
  APPROVE=""
done
node "$HERE/build-report-lite.mjs" "$(cd "$HERE/../../.." && pwd)/.claude/hillclimb/ask-effort/"
echo "full eval finished — .claude/hillclimb/ask-effort/report.html"
