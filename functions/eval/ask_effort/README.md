# Ask reasoning-policy eval (Phase 8) — CLOSED

**Status: closed by the owner on 2026-09-26. No paid runs.** Every entry point
(`run.mjs`, `eval.sh`, `pilot.sh`, `full.sh`) refuses to make real Anthropic
calls (Ask turns or the Opus judge) unless `ZIVO_EVAL_PAID_APPROVED` is set —
and only the owner sets it, for a run they approved. `EVAL_DRY=1` (a fake
provider, no network) still works for plumbing checks.

## What it measured

The real `runAiTurn` (router → Anthropic provider → tools → validator) over a
snapshot of the owner's account loaded into a throwaway Firestore emulator
(`demo-zivo-eval`, port 8187 — never prod), clock frozen at the snapshot.
41 cases (`cases.json`): 11 real owner messages, 13 probes from
`docs/AI_COACH_TEST_REPORT.md`, 17 variations; en / ar / Arabizi.

Variants (`variants.json`): prod today (Sonnet 5, API-default reasoning), and
forced Haiku 4.5 low / Sonnet low / medium / high, and the policy in auto mode.
Forced Sonnet high is the **control**: the same effective setting as prod, so
its win rate is the noise floor.

Grading: free checks (clean ending, reply language, the diet validator, safety
guards) + a blind pairwise Opus 5 judge against prod's frozen reply.

## What ran (≈ $2.50 pilot + the partial full run)

| Run | Rows |
|---|---|
| Pilot: 8 cases × 6 variants × 1 rep | 48 turns + 40 judge calls |
| Full (interrupted): prod today | 41 × 2 = 82 turns (checks only) |
| Full (interrupted): Haiku low / auto | 8 / 11 turns (judged) |

Results are local and read-only in `.claude/hillclimb/ask-effort-pilot/` and
`.claude/hillclimb/ask-effort-full-partial/` (gitignored: traces quote the
owner's data). The snapshot is `fixture/owner.json` (gitignored, never
deployed — `eval/` is in firebase.json's functions ignore list).

## Findings that set the policy (`functions/ai/chat/reasoning_policy.js`)

| Setting | Judged turns | Win vs prod | vs control (~0.29) |
|---|---|---|---|
| Haiku 4.5 low | 18 | 0.00 | clearly worse (Egyptian-dialect slips, English preambles) |
| Sonnet low | 8 | 0.38 | no measurable loss |
| Sonnet medium | 13 | ~0.31 | no measurable loss |

Low/medium cut output tokens ~35–40%; overall that's ≈8% cost per turn (output
is ~16% of cost). Small samples — ambiguous and safety turns stay at high.

## Separate findings (not fixed in Phase 8)

- ~~Routing gaps~~ — FIXED 2026-09-26 in `ai/chat/intent.js`: "متمرنش…"
  (Egyptian negation م…ش), "انا بضخم", "sugar", "3amel eh ya coach",
  "شكرا يا كوتش" no longer AMBIGUOUS; "What does creatine actually do?" is
  GENERAL (a knowledge question with no figures to look up).
- Sonnet sometimes answers Arabic in English ("مش عندي فول مدمس", 3 variants
  incl. the control; "التمرين الجاي ايه؟" mostly English in both prod reps).
  Arabizi got Arabic-script replies in both prod reps — possibly intended.
- "Log 3 eggs and a banana" ended `tool-error` in both prod reps.
- Several Sonnet replies (incl. prod's) claimed the plan has no rest day;
  the rotation has one ("حابب اعرف عادي متمرنش…").
