# ADR-015 — Daily Readiness: a fused, derived recovery call

**Status:** accepted · 2026-09-12
**Context:** [`lib/features/readiness/`](../../lib/features/readiness/FEATURE.md) ·
one new collection (`stepDays`, groundwork) · a **staged** backend tool
(`get_readiness`, deploy-gated) · no new client dependency

## Context

`docs/PRODUCT.md` lists **Readiness signals** as a wedge direction — "fold
already-captured data (body-weight trend, step count) into coaching" — and says
it needs an owner decision and an ADR first. ZIVO already holds the pieces a
readiness call is made of: last night's sleep (with provenance), the workout
analytics engine's stall verdicts, session history, and a body-weight trend.
Nothing fused them into a single "what should I do today" answer.

The owner asked to build it, choosing: the **Daily Readiness score** as the
spine with **auto-deload folded in** as one of its signals; a visible client
card now with the coach integration **staged** for a later deploy; and steps
**deferred** (only today's live count exists — no history) with snapshot
groundwork started now.

## Decision

**One deterministic call — `trainHard | goLight | rest` — fused on the client
from data ZIVO already holds, every factor citing the number behind it.**

### Derived, never stored

Readiness is computed on demand from existing streams (sleep nights + targets,
sessions, body-weight), exactly as `SleepGlanceSection` derives from nights.
There is **no readiness collection** — a stored score would be a second source
of truth that drifts from its inputs. The only new persistence is `stepDays`
(below), which readiness does not yet read.

### It fuses; it does not re-derive

The engine (`domain/readiness.dart`) reads other engines' verdicts, never their
internals: the stall/deload signal comes from `analyzeTraining()`'s
`needsAttention` / `overallStatus`; sleep facts from `SleepNight` +
`SleepTargets`; weight from `computeWeightTrend()`. This is the same rule the AI
coach follows, and it is why the card and the Workout screens can't disagree.

### The gate returns null

With nothing to stand on — no recent sleep, no training, no weigh-in —
`computeReadiness` returns null and the Today card **hides**, like the sleep
glance. A fabricated call or a zero would be a statement about the user that
isn't true. Sleep is only used when the night is genuinely recent (age ≤ 1);
an old night is never dressed up as "last night".

### How the call is made (deterministic, documented)

Each signal contributes a direction — `supports` / `caution` / `limits`:

- **Sleep** vs the duration target: ≥90 min short = limits, ≥30 min short =
  caution, else supports (judged against the night's snapshot target, else the
  current target, else the neutral 8h default — used only to *judge*, never
  shown as an adherence figure).
- **Deload** (auto-deload, folded in): ≥2 stalled/regressing lifts, or an
  overall regression = caution.
- **Recovery**: ≥2 calendar days since the last session = supports; trained
  today = caution; one rest day is neutral.
- **Body weight**: a loss ≥2 kg over the trend window = caution (the softest
  signal, conservative on purpose).

Combine: `debt = 2·limits + cautions`. `debt ≥ 3` → rest; `debt ≥ 1` → go light;
`debt 0` → train hard only with a genuine supporting signal, else go light (the
honest default over claiming you're primed on no evidence).

### Colour carries status, not a new hue

Per [ADR-006](ADR-006-one-design-system.md) hue discipline and the Analysis
screens' precedent, the verdict uses the app's status semantics — green = train
hard, amber = go light, ember = rest — rather than inventing a fifth hue.

### The coach opens with it — staged

The visible card **is** the coach opening with the call. A backend read tool
`get_readiness` + a `chat/prompt/sections/training.js` note are committed and
tested offline (`functions/ai/readiness.js` mirrors the Dart combination layer,
pinned by `test/fixtures/readiness_vectors.json` which both suites run), but are
**not live until `firebase deploy --only functions`** — an owner action. Until
then the card stands alone and the coach does not yet cite the score. This keeps
the whole feature landable without credentials.

### Steps deferred, snapshots started

`StepCounterService` only exposes *today's* live count, so steps can't feed a
"low vs your normal" judgement yet. v1 fuses sleep + training + weight, and a
small `StepDayRepository` writes `users/{uid}/stepDays/{yyyy-MM-dd}` from now on
so a history accrues for a later readiness input. It is write-only groundwork —
nothing reads it back yet — but a new collection still gets a rule and a rule
test.

## Consequences

- Readiness is only as good as its inputs; with sparse data it stays quiet (the
  gate) rather than guessing. That is the intended failure mode.
- It is **not** an Oura/WHOOP-style physiological score — ZIVO has no HRV, resting
  HR, or temperature. The detail page and the coach both say so. Adding such
  inputs would be a later decision, not a silent extension of this one.
- Deploying the functions changes the coach's behaviour (it will lead with the
  readiness call); until then there is a deliberate, documented gap between the
  card and the coach.

## Not done (deliberate)

The sleep→performance correlation insight; a standalone deload UI beyond the
readiness factor; consuming `stepDays` in the engine; any recovery-hardware
signal.
