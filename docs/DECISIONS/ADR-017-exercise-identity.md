# ADR-017 — Exercise identity: canonical exercise, plan slot, shared history

**Status:** accepted · **Date:** 2026-09-25 · **Supersedes** the "a split's
history is its own" rule (WORKOUT_SYSTEM.md §3.2 invariant 4).

## Context

There was no concept of an exercise, only plan slots. `PlannedExercise.id` is
minted per slot (`<plan>-d<i>-e<j>` on import, a timestamp by hand), and every
session copied it into both `SessionExercise.id` and `.exerciseId`. Every
progression engine keys on `exerciseId`, so:

- the same movement on two days had two unrelated histories — in the owner's
  own split, 7 repeated movements (Pec Deck, Preacher Curl, Cable Lateral
  Raise(s), Zigzag/EZ Pushdown, Wide-Grip Seated Row, Hammer Curl, Rear Pec
  Deck) were each split in two;
- the live session filtered history by `planId`, so switching splits reset
  progression, while the Analysis hub read every split — two different answers;
- names cannot fix it: exact matching catches 2 of those 7, and loose matching
  would merge Incline Dumbbell Press with Incline Machine Chest Press.

## Decision

Three concepts, three ids:

1. **Canonical exercise** (`CanonicalExercise`, `users/{uid}/exercises`) — the
   exact movement/variation/equipment. Clean: name, equipment, muscle group.
2. **Plan slot** (`PlannedExercise.id`, unchanged) — where it sits in a split
   and what it prescribes there. Gains `exerciseId` → the canonical exercise.
   **A slot without one is its own exercise** (`canonicalId == id`), which is
   exactly the pre-ADR behaviour, so no plan needs migrating to keep working.
3. **Progression history** — every `SessionExercise` whose `exerciseId`
   resolves to the canonical id. Sessions now also store `slotId`
   (`effectiveSlotId` falls back to `id` for older records).

**Legacy ids live in a separate alias layer** (`users/{uid}/exerciseAliases/
{legacyId}` → `canonicalId`), not on the canonical exercise. The
`ExerciseIdentityResolver` applies aliases **when history is read**
(`canonicalize`) and never writes back, so no session is ever rewritten and
removing an alias restores the old reading exactly.

Read-side rules:

- **History follows the exercise across days and splits.** The live session
  no longer filters by `planId`.
- **"Last time" / goals are slot-first**: the same slot's last performance
  wins; the exercise's wider history is the fallback (`lastPerformanceFor(…,
  slotId:)`). The same lift is often prescribed differently on two days.
- Trends, PRs, strength and adherence read the whole canonical history.
- Names only *suggest* identity (`matchExercise`): different known equipment
  is never a match, variation words (single-arm, incline, seated…) make a
  different exercise, and only same-words + same/no equipment is "confident".

## Consequences

- Resolution happens at the readers (live controller, Analysis, per-exercise
  analysis, Readiness, PR detection) — not in the session repository, where a
  re-save could persist resolved ids.
- New rules + rule tests for both collections. Embedded plan/session exercise
  fields are unvalidated by the rules, so `exerciseId`/`slotId` needed none.
- Not yet done (next increments): the matcher wired into manual add / import
  review / plan-editor rename; the one-time migration and "these look like
  the same exercise" review card; the Node mirror (`functions/ai` analytics +
  the coach's name resolver) reading aliases. Until the migration writes
  aliases or slot `exerciseId`s, every account reads exactly as before.
