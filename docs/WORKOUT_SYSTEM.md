# ZIVO — Workout System: Source of Truth

> **Purpose.** This is the single all-in-one context file for ZIVO's Workout
> system. If you open a fresh AI/Cursor/Claude chat, read this file first: it
> explains what we are building, how the system is designed, what is already
> done, and what the next step is. Keep it current — every completed phase
> updates the **Status** section below.

---

## 0. Status (read this first)

**Branch:** `feature/workout-diet-v2` (this milestone continues here — no new branch).

**Sequencing decision:** *Analysis first, retrofit splits.* We ship the
progressive-overload analysis page on the current single-active-plan data,
then introduce first-class Splits and re-scope analysis to them. (The
alternative — splits foundation first — was considered and declined for
speed of a visible result.)

**Workflow (every phase):** plan → implement → test → verify → **commit**.
Each completed phase is its own commit so we always have clean checkpoints.
Keep work uncommitted until a phase is green (`flutter analyze` clean +
`flutter test` passing); watch the repo's auto-commit tool and check
`git log` before/after any git action.

| Phase | What | State |
| --- | --- | --- |
| 0 | This source-of-truth doc + data-model/invariants locked | ✅ done |
| 1 | Collapsible/expandable day tiles in Edit Workout Plan | ✅ done |
| 2 | Progressive-overload **Analysis page** (current single-plan data) | ✅ done |
| 3 | **Splits** data foundation (multi-split repo + migration + `splitId` on sessions) | ✅ done |
| 4 | Split **management UX** (create / switch / edit / delete, isolated history) | ⬜ not started |
| 5 | **Retrofit** analysis + history to be split-scoped | ⬜ not started |
| 6 | **AI PDF import** (Cloud Function extractor + review-and-confirm UI) | ⬜ not started |
| 7 | End-to-end verify + handoff doc refresh | ⬜ not started |

**Phase 1 notes:** `_DayCard` (`workout_plan_edit_page.dart`) is now a
collapsible tile — collapsed shows the header + exercise count only;
tapping it springs open (critically damped, `AppSprings.standard`,
interruptible) to reveal exercises/notes/"Add exercise", with a rotating
chevron. Days start collapsed except one just added in this session (auto-
expands — you're clearly about to fill it in). Multiple days can be open at
once (not a forced accordion — useful for cross-referencing two days while
editing). Expand state is keyed per day id, so it survives unrelated edits
elsewhere on the page rather than resetting. Reduced motion snaps instantly
(no spring). No existing behavior changed — edit/remove/notes/Default-rest
bulk row/add-day/add-exercise all still work, including while expanded;
only the exercises' *visibility* is now gated on expand state.

**Phase 1 addendum — long-press drag-to-reorder (added after the owner felt
the collapse/expand live, wanted reorder too):** both the day list and each
day's exercise list are now `ReorderableListView.builder`s
(`buildDefaultDragHandles: false`, `onReorderItem` — not the deprecated
`onReorder`), with each item wrapped in `ReorderableDelayedDragStartListener`
so a long-press starts the drag while a plain tap still reaches the header's
expand toggle / a row's edit tap underneath — Flutter's own primitive for
exactly that coexistence, not hand-rolled gesture-arena code. A custom
`_liftProxyDecorator` replaces the default drag proxy: scale ~1.03,
elevation/shadow, slight dim, matching each item's own corner radius;
`onReorderStart`/`onReorderEnd` fire `selectionClick`/`lightImpact` haptics.
Reduced motion drops the lift flourish (the reorder stays fully functional).
Auto-scroll and 1:1 tracking/reflow come from `ReorderableListView` itself —
deliberately not reimplemented from scratch.
- **Known constraint, flagged rather than hidden:** the exercise list nested
  inside a day card is `shrinkWrap: true` + `NeverScrollableScrollPhysics`
  (it has no scroll extent of its own), and doesn't inherit real auto-scroll
  from the page's outer scrollable — dragging an exercise past the day
  card's own visible bounds can fail to complete the reorder. Low real risk
  for a typical handful-of-exercises day; would need addressing if a day
  ever has enough exercises to make that drag distance common.
- **Rotation-cursor semantics, decided:** reordering days reassigns each
  day's `order`, and `WorkoutPlan.cycleCursor`/`nextDay` — read by BOTH Home
  and the Workout page — is an `order`-indexed pointer. So the cursor is now
  tracked by the DAY'S IDENTITY it pointed at when editing opened (not a raw
  index), and resolved back to that day's new index on save — reordering
  days can never silently change which workout is "next." A day that gets
  removed falls back to index 0.
- The manual `if (newIndex > oldIndex) newIndex -= 1` adjustment Flutter's
  own reorder examples use isn't needed — `onReorderItem` already delivers a
  final, ready-to-insert index.

**Phase 2 notes:** the progressive-overload Analysis page — day picker,
per-exercise last-vs-previous deltas/verdict (reusing `compareToLastTime`/
`lastPerformanceFor`, not reinvented), a dependency-free `CustomPainter` trend
chart tinted by verdict, and a shared `verdictStyle()` so the live session's
set badge and the analysis badges read as one system. Committed
(`feat(workout): progressive-overload analysis page`).

**Phase 3 notes:** `WorkoutPlanRepository` is now a multi-split repo + active
pointer, extended additively (`activePlan`/`watchActivePlan`/`savePlan`/
`deletePlan` still work unchanged) — in-memory (seeded active from the owner's
real split) and Firestore (`workoutMeta/active` pointer doc, migration-on-read
falling back to the first `status==active` plan when no pointer exists yet, so
existing users lose nothing) both implemented and covered (in-memory 19 cases +
Firestore 10, via `fake_cloud_firestore`). Committed
(`feat(workout): first-class splits data foundation (multi-split repo +
migration)`).
Two invariants from §3.2 landed alongside: `LiveSession.splitId` is a
documented getter alias for `planId` (the doc's own `splitId (=planId)`
notation — no new stored field, no serialization change), and the
exercise-id-preservation behavior (edit-in-place keeps `PlannedExercise.id`;
add, or a name-identical remove+re-add, mints a fresh one) turned out to
already be correct in `workout_plan_edit_page.dart` — pinned with a
through-the-UI regression test (`plan_edit_exercise_identity_test.dart`) so a
future refactor can't silently break it.
**Deliberately out of this phase:** split management UX (create/switch/edit/
delete splits — Phase 4) and on-device simulator verification of the splits
plumbing (nothing here is UI-visible yet; the next UI-facing phase is 4).

---

## 1. Vocabulary (use these words precisely)

- **Split** — a named workout configuration/template (e.g. "Push Pull Legs",
  "Arnold Split"). A user has many saved splits; exactly **one is active** at
  a time. A split owns its own days, its own history, and its own analysis.
  *In code, a Split is a generalized `WorkoutPlan`.*
- **Plan / `WorkoutPlan`** — today's model for the (single) active split: a
  named, ordered **rotating cycle** of days (`cycleCursor` picks the next
  day; not tied to weekdays). Fields: `id, name, status, source, createdAt,
  updatedAt, days, cycleCursor`. `source` is `manual | pdf` (`pdf` already
  reserved).
- **Day / `WorkoutDay`** — one day in the rotation: `slot` ("A"/"B"/"C"),
  `label` ("Push"), `order`, `notes`, `exercises`.
- **Planned exercise / `PlannedExercise`** — a movement in a day: `id, name,
  order, muscleGroup, notes, defaultRestSeconds, sets` (planned `PlannedSet`s).
- **Session / `LiveSession`** — a live or completed *execution* of a day.
  Rich log: carries `planId`, `dayId`, per-exercise `exerciseId`, executed
  `sets` (with `done`, actual reps/weight), `status`, `startedAt`,
  `completedAt`. **This is the entity analysis is built on.**
- **Workout log / `Workout`** — a *flattened* "what happened" record (`title,
  performedAt, exercises[name/sets/reps/weightKg]`). Used on Home/History.
  **Has no split/day/exercise ids** — do not build analysis on this; it is a
  display projection, not the analytical source.
- **Progressive overload** — trained the same movement over time and moved a
  meaningful metric up (weight, reps, or volume = reps × weight).

---

## 2. What already exists (do not rebuild)

- **`WorkoutPlan` is already split-shaped** — named, dayed, with a reserved
  `pdf` source. The only gap for splits: the repo enforces a single active
  plan (`WorkoutPlanRepository.activePlan / watchActivePlan / savePlan`
  replaces by id).
- **History is already split-scopeable** — `LiveSession` carries
  `planId + dayId + exerciseId`, so completed sessions can be filtered to a
  split and a day today.
- **Progression math is done** (set-level):
  - `progression.dart` — `computeGoal(...)`: double-progression target.
  - `progress_comparison.dart` — `compareToLastTime(...)`: reps % / weight Δ /
    volume % / overall %, rolled into `ProgressVerdict {progressing, matched,
    down}`.
  - `exercise_history.dart` — `lastPerformanceFor(exerciseId, pastSessions)`:
    most recent completed session for an exercise; `ExerciseHistory` with
    index-aligned done sets + `topWeightKg`.
  The **analysis page aggregates these**; it does not reinvent the math.
- **AI backend is mature** — an `aiChat` **Cloud Function** gateway
  (`functions/`), client is server-write-only, with an **action-proposal
  pattern** (ADR-003: AI proposes a structured action → user confirms/cancels
  → server writes). **PDF import reuses this shape.**

---

## 3. Target architecture

### 3.1 Splits (generalize the single plan)

- A **Split is a `WorkoutPlan`**. Move `WorkoutPlanRepository` from
  *one active plan* → *a set of splits + one active pointer*:
  - `watchSplits()` → all saved splits; `watchActivePlan()` keeps returning
    the active one (back-compat); `activeSplitId` pointer; `setActiveSplit(id)`;
    `saveSplit` (create/replace by id); `deleteSplit(id)` (history is retained
    or archived, never silently destroyed).
  - **Migration:** the existing single active plan becomes the first split;
    `activeSplitId` points at it. No user data lost.

### 3.2 History & edit invariants (the part that must be right)

1. **Completed sessions are immutable.** A `LiveSession` once completed is
   never rewritten by later plan edits.
2. **Sessions are stamped with context:** `splitId` (= `planId`) + `dayId` +
   per-exercise `exerciseId`, **plus a snapshot of the exercise name/prescription
   at log time**, so renaming or reordering later never corrupts past records.
3. **Editing a split preserves identity for unchanged exercises** — same
   `exerciseId` ⇒ history stays linked. **Replacing/changing an exercise mints
   a new `exerciseId`** ⇒ a fresh history line; the old exercise's history is
   preserved under its old id, never mixed with the new movement.
4. **Switching splits** only moves the active pointer. Every split keeps its
   own sessions; analysis for split X reads only split X's sessions.
5. **Comparing the same exercise across sessions** keys on `exerciseId`
   (stable), not on the display name (which can change).

### 3.3 Progressive-overload analysis

- **Scope:** a chosen **day** within a split (e.g. "Push"), comparing the two
  most recent completed sessions of that day — and per-exercise trends across
  the last N sessions.
- **Per exercise:** weight ↑/↓ (top set + per-set), reps ↑/↓, volume change,
  a Progressing/Matched/Down verdict (reuse `compareToLastTime`), best/PR
  weight, and a small trend line over recent sessions.
- **Per day/session:** total volume trend, an overall progression verdict,
  count of exercises improved/matched/regressed.
- **Data source:** completed `LiveSession`s filtered by (active split's)
  `planId` + `dayId`. Never the flat `Workout` log.
- Handle first-time / single-session gracefully (nothing to compare → a clear
  "log another session to see progress" empty state).

### 3.4 AI PDF import

Flow: **Import PDF → AI reads & understands → extracts workout structure →
mapped into our model → user reviews → confirmed → saved as a Split
(`source: pdf`).**

- **Server-side** (a new callable Cloud Function in the existing gateway
  style, e.g. `aiImportWorkoutPlan`): receives the PDF (or its extracted
  text), calls the model with a **structured-output schema** matching our
  domain (days → exercises → sets, rep targets, rest, muscle group), returns a
  proposed split. Keys stay server-side. *(Confirm which model the existing
  gateway uses before wiring; match it unless there's reason to differ.)*
- **Client:** import entry point → progress state → a **review screen** (the
  action-proposal/confirm pattern) where the user can eyeball/fix the parsed
  structure → confirm creates the split. Never auto-commit an unreviewed import.
- **Robustness:** the model may misread; the review step is mandatory, and the
  extractor must degrade gracefully (partial parse → editable draft, not a
  hard failure).

---

## 4. Firestore layout (target)

```
users/{uid}/
  workoutSplits/{splitId}          # was the single active plan; now many
    (WorkoutPlan fields incl. days[], source, cycleCursor)
  workoutMeta/active               # { activeSplitId }
  workoutSessions/{sessionId}      # LiveSession; stamped splitId+dayId+exerciseId
  workouts/{workoutId}             # flat Workout log (display projection)
  aiConversations/{id}/messages    # existing AI (server-write-only)
```

Security rules follow the existing pattern (user-owned subtrees; AI writes via
Cloud Functions only). Add a `schemaVersion` to new docs for migration safety.

---

## 5. Phased implementation plan (executable, commit per phase)

Each phase: **plan → implement → test → verify → commit.** Suggested commit
message prefixes in parentheses.

### Phase 0 — Source of truth + model lock  *(docs)*
- Land this file. Confirm the data model + invariants in §3. No feature code.
- **Commit:** `docs(workout): add Workout System source-of-truth + phased plan`.

### Phase 1 — Collapsible day tiles  *(quick, independent)*
- In `workout_plan_edit_page.dart`, make each `_DayCard` an expand/collapse
  tile: collapsed shows `Day {slot} · {label}` + exercise count; tapping
  expands to the `_ExerciseRow`s. Default collapsed (or remember last).
- Apple-polished: spring expand/collapse (critically damped), animate height +
  a chevron rotation; respect `prefers-reduced-motion`. Not a raw
  `ExpansionTile` if it can't be made to feel premium.
- **Tests:** widget test — tapping a day toggles its exercises' visibility;
  reorder/edit still work while expanded.
- **Verify:** run the app, expand/collapse each day, confirm editing the last
  exercise no longer needs a long scroll.
- **Commit:** `feat(workout): collapsible day tiles in Edit Workout Plan`.

### Phase 2 — Progressive-overload Analysis page  *(on current single plan)*
- New page under the workout section (reachable from Hub → Workout and/or the
  Training card). Pick a **day** (default the active/next day), show:
  - Last-session vs previous-session comparison per exercise (reuse
    `compareToLastTime` / `lastPerformanceFor`), with weight/reps/volume deltas
    and a Progressing/Matched/Down verdict.
  - A recent-sessions trend per exercise (top-set weight and/or volume).
  - A day-level overall verdict + improved/matched/regressed counts.
- **Data:** completed `LiveSession`s for the active plan's `planId`, grouped by
  `dayId`. Add a repository read for session history if one isn't already
  exposed (`watchSessions()` / `pastSessions`).
- Empty/first-time states handled.
- **Tests:** unit tests for the aggregation (given N sessions → expected
  deltas/verdicts/trends); widget test for the page states (empty, one
  session, multiple).
- **Verify:** run the app on real/seed history, confirm numbers match hand
  calculation for a known day.
- **Commit:** `feat(workout): progressive-overload analysis page`.

### Phase 3 — Splits data foundation  *(retrofit begins)*
- Generalize `WorkoutPlanRepository` to multi-split (§3.1): `watchSplits`,
  active pointer, `setActiveSplit`, `saveSplit`, `deleteSplit`. Keep
  `watchActivePlan` working.
- Firestore layout §4 + **migration** of the current plan into `workoutSplits`
  with `activeSplitId` set. In-memory + Firestore impls both.
- Stamp `splitId` on new/edited `LiveSession`s; enforce exercise-id
  preservation on split edits (§3.2 invariants 2–3).
- **Tests:** repo tests for multi-split CRUD + active pointer; migration test
  (single plan → one split, no data loss); edit-preserves-exerciseId test;
  Firestore round-trip.
- **Verify:** app still boots with existing data (migrated), active split shows
  as before.
- **Commit:** `feat(workout): first-class splits data model + migration`.

### Phase 4 — Split management UX
- UI to list splits, switch active, create, edit (reuse the plan editor),
  duplicate, delete. Switching must not touch history.
- **Tests:** widget tests for create/switch/delete; switching split A→B→A keeps
  each split's history intact.
- **Verify:** create a second split, switch back and forth, confirm history and
  analysis stay correct per split.
- **Commit:** `feat(workout): split management (create/switch/edit/delete)`.

### Phase 5 — Retrofit analysis + history to splits
- Re-scope the Phase 2 analysis and any history views to the **active split**
  (filter by `splitId`), so each split has independent analysis. Cross-split
  data never mixes.
- **Tests:** analysis for split X excludes split Y's sessions; same-exercise
  comparison keys on `exerciseId`.
- **Verify:** two splits with distinct histories show distinct analysis.
- **Commit:** `refactor(workout): scope analysis + history to active split`.

### Phase 6 — AI PDF import
- Cloud Function `aiImportWorkoutPlan` (§3.4): PDF/text → structured split
  proposal. Client import → review/confirm (action-proposal pattern) → save as
  a split (`source: pdf`).
- **Tests:** function-level extraction test against a sample PDF/text fixture
  (structure maps to our model); client review-screen widget test (edit before
  confirm; confirm creates the split; cancel discards).
- **Verify:** import a real PDF end-to-end, review, confirm, see the new split.
- **Commit:** `feat(workout): AI PDF import → structured split`.

### Phase 7 — Verify + handoff
- End-to-end pass of all flows; update this doc's **Status** table and
  `docs/PROJECT_CONTEXT.md` handoff with what's done + what's next.
- **Commit:** `docs(workout): mark splits/analysis/AI milestone complete`.

---

## 6. After implementation — recommended next steps

Once the phases land, the sensible follow-ups (verify/test/review/build):
- **Verify with real data:** import your actual PDF, run a full session against
  a split, confirm analysis reflects the real progression.
- **Review:** a focused code review of the splits data model + migration
  (highest-risk area) and the AI extraction prompt/schema.
- **Test depth:** add fixtures for messy real-world PDFs; property-test the
  progression aggregation.
- **Build next:** AI-driven progression *suggestions* (the assistant reading
  your analysis and recommending next weights/reps), diet/nutrition tie-in, and
  wiring the analysis verdicts back into the live session Goal card.

---

## 7. Decisions log

- **2026-08-19** — Sequencing: **analysis first, then retrofit splits** (speed
  of a visible result over foundation-first purity).
- **2026-08-19** — Branch: **continue on `feature/workout-diet-v2`** (no new
  milestone branch for this work).
- **2026-08-19** — A **Split == generalized `WorkoutPlan`**; history scoped by
  `splitId (=planId) + dayId + exerciseId`; analysis built on `LiveSession`,
  not the flat `Workout` log.
- **2026-08-19** — AI PDF extraction runs **server-side** in the existing
  Cloud Function gateway, using the action-proposal/confirm pattern; imports
  are always user-reviewed before saving.
