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
- **Migration + sync** (`identity_reconcile.dart`, `ExerciseIdentitySync`,
  wired at app root on sign-in/resume and after splits change). One pure,
  deterministic, idempotent pass: every slot and every id only history
  remembers gets a canonical exercise; a **confident** name match joins an
  existing one, anything less gets its own; each legacy id gets a
  `migration` alias; slots get their `exerciseId` filled on the LIVE split.
  Ids are `x-<legacyId>`, so two devices migrating at once write the same
  docs. It waits for the library, splits and history to have really loaded
  (`ExerciseLibrary.loaded`) — an empty-because-not-read library would mint
  duplicates. It never writes a session. The same pass links new imports and
  in-session adds afterwards, so no flow needs its own matcher call.
- **"Same exercise?"** — plausible pairs (e.g. Hammer Curl / Hammer Dumbbell
  Curl: one name states equipment, the other doesn't) are never merged by
  the pass; the Analysis hub asks. "Same" writes a `merge` alias (keeping
  the more specific name), with Undo; "Keep separate" is remembered in
  `CanonicalExercise.distinctFrom` (rules + rule test).
- **Plan-editor rename**: a typo fix keeps the identity; a rename to a
  different movement (`isDifferentMovement`: other known equipment, a
  variation word gained/lost, or no movement word in common) gives the slot
  a new identity, so a variation never inherits another's history.
- **In-session swap/add** resolve the pick through `resolveExerciseChoice`
  (library id kept, confident name match linked, else a new exercise). A
  swap keeps logged sets on the original exercise and moves only pending
  sets to the substitute, which keeps the slot but not the target loads.
- **Node mirror**: `functions/ai/analytics/exercise_identity.js` +
  `store.listExerciseAliases`; the coach's workout reads
  (`loadResolvedSessions`) and `analyzePlanAdherence` key on the canonical
  exercise exactly as the app does. Any name an exercise was logged under
  finds it in `get_exercise_analysis`.
