# ADR-019 — Rest days are a day type; what was planned is derived, what happened is recorded

**Status:** accepted · 2026-09-25
**Context:** [`lib/features/workout/`](../../lib/features/workout/FEATURE.md) ·
extends [ADR-012](ADR-012-streaks-and-session-duration.md) (the streak rule) ·
touches the coach ([`functions/ai/`](../../functions/ai/README.md))

## Context

Every `WorkoutDay` was a workout. A plan that said "Wednesday — Rest" was
imported as a workout called "Rest" with zero exercises, so Today offered
**Start** on `0 exercises · 0 sets`, and it sat in the rotation as a session
the user could never complete. ADR-012 had already noted the gap: "a rest day
was not even representable".

A second gap: a user who decided not to train today had no way to say so. Not
opening the app and choosing to rest were the same empty day, so nothing
downstream — adherence, the streak, the coach — could tell "rested on purpose"
from "didn't show up".

The request that prompted this described a **weekday** plan
("Monday → Upper, Wednesday → Rest"). ZIVO's plan is not a weekday calendar;
it is a **rotation** (`WorkoutPlan.cycleCursor` advances when a day is
trained, ADR-008, and the coach's `change_workout_day` mirrors that). Turning
the plan into a calendar would have rewritten the rotation, the swap/skip
rules, the editor, the coach's mutation and every stored plan, for a product
that deliberately doesn't care which weekday it is. That was not done.

## Decision

1. **`TrainingDayType { workout, rest }` on `WorkoutDay`.** Persisted as
   `type: 'rest'` and omitted for a workout, so every stored plan reads back
   unchanged and older app versions keep reading new ones. A rest day never
   carries exercises (import, editor and normalization all enforce it).
   One model for import, the editor and any future AI-generated plan.
2. **A rest slot is a place in the cycle, not a workout.** `nextDay` reads past
   rest to the next workout (so nothing ever "starts" a rest day), `swapDays`
   refuses rest, the Change sheet lists workouts only, and the Node rotation
   (`workout_rotation.js`) applies the same three rules.
3. **What was PLANNED on a date is derived, never stored**
   (`domain/training_days.dart`). A rest slot follows the workout before it
   ("Lower → Rest → Push"): the N days right after training a workout followed
   by N rest slots are *planned rest*; every other day has a workout due, and
   the rotation waits for it — exactly how the cursor already behaved. This is
   a pure function of the plan and the session history, so there is no second
   source of truth to drift.
4. **What the user CHOSE is a day mark, not a plan edit.** "Take a rest day"
   writes `trainingDayMarks/{today}` with `reason: rest` — the existing
   per-day record ADR-012 introduced for missed-day reasons. The plan is never
   touched: skipping Shoulders to rest leaves Shoulders up next. A retroactive
   "I rested" on a past day is the same statement and the same record; every
   other reason (travel, illness…) stays context on a day that remains missed.
   No Firestore rule change was needed (`rest` was already an allowed reason).
5. **One classification, six outcomes:** `completed`, `missed`, `userRest`,
   `plannedRest`, `extraWorkout` (trained on planned rest), `pending` (today,
   still open) — plus **`unscheduled`**, see below. Summaries keep them apart
   (planned vs completed vs missed workouts, chosen vs planned rest, extra
   workouts, actual vs planned training days per week, which days get skipped,
   per-week counts). Never collapsed into one streak number.
6. **"Missed" requires a plan that schedules its rest.** A pure rotation
   (Push → Pull → Legs, every existing plan) leaves rest implicit; calling
   each unlogged day missed would turn the rest it assumes into failures. On
   such plans the day is `unscheduled`, and planned-workout / missed /
   planned-frequency figures are **null**, not zero.
7. **The streak honours planned rest, not chosen rest.** Planned rest days no
   longer consume the 3-day allowance (a two-day split with three rest days in
   a row is following its plan). A chosen rest gets no extra pass — the normal
   allowance already covers honest rest, and restores remain the one repair.
   Every streak surface (Today's Momentum row and insight, the Orbit, the hub
   tile, the streak page, the restore check) now passes the same inputs.
   Today's Momentum row previously ignored restores altogether; it no longer
   does.
8. **The coach reads it through the same engine.** `analytics/training_days.js`
   mirrors the Dart engine, pinned by `test/fixtures/training_days_vectors.json`
   (both suites run it). `get_training_analysis` carries a `trainingDays`
   block (last 28 days), and `get_workout_schedule` marks rest slots and says
   whether today is planned or chosen rest. The prompt forbids inventing
   reasons or medical claims from it, and forbids rewriting the plan.

## Consequences

- **Past days are judged against the plan as it is now.** There is no plan
  version history; edit the split and old days are reclassified against the
  new shape. Days before the plan's `createdAt` are never judged.
- **The due workout on a past day is the rotation's best reconstruction**
  (the workout after the last one trained; the live cursor once past the last
  logged session). Swaps and skips made on the day are not replayed.
- **A plan whose cycle begins with rest** shows that rest only after a workout
  precedes it; before any history the first workout is due.
- **A session from another split** counts as training that day but does not
  move this rotation.
- Not added (no product need yet): rest *reasons* beyond the existing mark
  reasons, auto-adapting the plan to behaviour, a rest-day management screen.
