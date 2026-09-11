# workout — feature map

> The largest feature (~73 files). Splits, live guided sessions, progression analysis,
> body-weight tracking, and AI PDF plan import. Deep doc: [`docs/WORKOUT_SYSTEM.md`](../../../docs/WORKOUT_SYSTEM.md).

## Start here (entry pages — `presentation/pages/`)

| Page | Role |
|---|---|
| `workout_dashboard_page.dart` | Main workout surface / interactive dashboard |
| `workout_plan_page.dart` | View the active split's plan |
| `workout_plan_edit_page.dart` | Edit a split — **renders + owns its sheets**; the document is `presentation/controllers/plan_edit_controller.dart` (day/exercise mutation and the rotation-cursor rule) |
| `split_management_page.dart` | Create / switch / edit / delete splits (multi-split) |
| `live_session_page.dart` | The guided live workout session — **renders only**; its logic is `presentation/controllers/live_session_controller.dart` (see below) |
| `session_details_page.dart`, `workout_history_page.dart` | Past sessions + history |
| `workout_analysis_page.dart`, `exercise_analysis_page.dart`, `workout_stats_pages.dart` | Progress/analysis. `workout_analysis_page.dart` is the **coaching hub** and the Workout tab's one deep surface — the dashboard's header "Analysis" pill opens it directly (there is no separate Progress landing any more; `workout_progress_page.dart` was **retired** in the 2026-09-11 redesign, its Plan/History/Splits links folded into this page's "Go deeper" card and its overview stats already living on the dashboard tiles). Organised as a slim summary (overall verdict · volume · recent PRs · focus next) over a **searchable, muscle-category-grouped exercise browser** (`_ExerciseBrowser` — Chest · Back · Legs · Shoulders · Arms · Core · Other, filtered live by name; each row carries its own status colour), then **what's being skipped**, then the always-present **"Go deeper"** destinations (Plan · All history · Splits). Reads `analytics/workout_analytics.dart` (`ExercisePerformance.muscleGroup` is the grouping key) + `analytics/plan_adherence.dart`. This replaced the old verdict-grouped stack (going-well/getting-worse/stalled/all-exercises), where a lift appeared in two lists at once. **Every exercise/PR/skip row taps into `exercise_analysis_page.dart`**, the per-exercise drill-down (status + what-happened/why/do insight · strength/volume trend · at-a-glance metrics · PRs · **session-by-session history with per-session deltas**) reading `analytics/exercise_analysis.dart`. Direction word/colour/icon come from the shared `widgets/progress_status_style.dart`; muscle-bucket → localized label is `presentation/workout_labels.dart`'s `muscleGroupLabel`. **Colour on these screens carries status only** — green/amber/ember mean progressing/stalled/declining, decorative icon tiles are neutral ink, and "focus next" is ember (the design system's Now/Next colour). |
| `workout_import_page.dart` | AI import → review UI, for a document (PDF/photo) **or** a dictated/typed description via `WorkoutImportInput` (pairs with `functions/ai/workout_import.js`). Was `workout_pdf_import_page.dart`. |
| `workout_describe_page.dart` | Say-it / type-it route — a thin wrapper over the shared `capture/presentation/import/plan_describe_page.dart` |
| `widgets/add_workout_sheet.dart` | `showAddWorkoutSheet` — the one doorway (document · say it · type it · build by hand); every entry point (hub, Today, split editor) opens it |
| `workout_settings_page.dart` | Training settings — the configurable maximum session length |
| `bodyweight_history_page.dart` | Body-weight log + trend |
| `workout_capture_page.dart`, `workout_day_details_page.dart` | Quick capture + day drill-in |

## The live session's three parts ([ADR-008](../../../docs/DECISIONS/ADR-008-presentation-controllers.md))

The session used to be one 4,236-line file. It is now:

| Where | What |
|---|---|
| `presentation/controllers/live_session_controller.dart` | **Everything the session *does*.** A plain `ChangeNotifier`: the rest / warm-up / elapsed clocks, the `SharedPreferences` countdown that survives an app kill, the debounced draft autosave, the history subscription, set resolution + undo, pause/resume, and `finish`/`leave`/`discard`. It never navigates and never holds a `BuildContext` — the page pops, and reduced-motion + the `TickerProvider` are passed in. |
| `presentation/pages/live_session_page.dart` | `build` and the four phase layouts (running · warm-up · resting · completed). |
| `presentation/widgets/live_session/` | The 9 files the ~30 private widget classes became — `session_header`, `goal_block`, `set_chips`, `rest_ring`, `set_input`, `session_review`, `up_next_card`, `session_effects`, plus `live_session_format.dart` (how ZIVO writes a weight, a rest, an elapsed time). |

The four phase layouts live in `widgets/live_session/phases/` — and warm-up and
rest are ONE `CountdownPhase`, because they were always meant to be the same
screen (the old comments said so while keeping two copies).

Session rules are unit-tested directly in `test/workout/live_session_controller_test.dart`
— no widget tree. `live_session_page_test.dart` still covers what the screen shows.

## The split editor ([ADR-008](../../../docs/DECISIONS/ADR-008-presentation-controllers.md))

`presentation/controllers/plan_edit_controller.dart` holds the days being
edited and, critically, the **rotation-cursor rule**: `WorkoutPlan.cycleCursor`
is an index, but days can be reordered, so the cursor is tracked by day id and
resolved back to an index in `buildPlan()`. Asserted in
`test/workout/plan_edit_controller_test.dart`. The page owns every sheet it
opens and the remove animations; widgets are in `widgets/plan_edit/`.

## Repositories (the seam — `domain/` interface, `data/` impls)

- **`WorkoutPlanRepository`** — splits/plans; `activePlan`, `watchActivePlan()`, `nextDay`.
- **`WorkoutSessionRepository`** — logged live sessions (in-memory variant can seed dev data via `dev_analysis_seed.dart`).
- **`WorkoutRepository`** — logged workouts.
- **`BodyWeightRepository`** — body-weight entries.
- **`WorkoutSettingsRepository`** — the account's training preferences (`users/{uid}/settings/workout`); currently the **maximum session length** (default 3h) that decides when a still-running session counts as one left open. [ADR-012](../../../docs/DECISIONS/ADR-012-streaks-and-session-duration.md)
- **`TrainingDayMarkRepository`** — one doc per calendar day (`trainingDayMarks/{yyyy-MM-dd}`): a missed-day **reason** (context only) and/or a spent streak **restore**. Deliberately NOT sessions — see the gotcha below.

Each has `firestore_*` + `in_memory_*` impls in `data/`, wired in
[`lib/app/app.dart`](../../app/app.dart), exposed via `AppScope` (`workouts`,
`workoutPlans`, `workoutSessions`, `bodyWeight`).

## Domain highlights (`domain/`)

- Plan model: `workout_plan.dart` → `workout_day.dart` → `planned_exercise.dart`, with
  `exercise.dart`, `muscle_group.dart`, `rep_target.dart`, `rest_policy.dart`, `set_type.dart`.
- Live session: `live_session.dart`, `session_exercise.dart`, `set_log.dart`,
  `session_phase.dart`, `session_status.dart`, and `live_session_to_workout_log.dart`.
- **Streak engine: `training_streak.dart`** — the ONE answer to "what is my
  streak", read by both the Workout hub and Today (`today_pulse.dart`
  delegates). Rule: a day counts once it has a **completed working set**, and
  the streak survives a gap of up to `kStreakMaxGapDays` (3) calendar days.
  Restores bridge a gap without adding a trained day; missed-day reasons are
  context and never move the number. All day maths goes through
  `core/util/calendar.dart`.
- **Session lifecycle extras: `session_maintenance.dart`** — the sweep that
  closes sessions left open, wired at app root (sign-in + resume) like
  `SleepService`, and deferring to whatever session a live screen has open.
- Progression/analysis: `progression.dart`, `day_progress_analysis.dart`,
  `progress_comparison.dart`, `weight_trend.dart`, `up_next_selection.dart`,
  `training_dashboard_stats.dart`.
- **Analytics engine: `analytics/workout_analytics.dart`** — the ONE centralized
  "how am I progressing" engine, consumed by BOTH the progress UI
  (`workout_analysis_page.dart`, `workout_progress_page.dart`'s summary card) and
  the AI coach (mirrored in `functions/ai/workout_analytics.js`, pinned by shared
  golden vectors). Pure over `List<LiveSession>`: `estimatedOneRepMax` (Epley,
  capped at 12 reps), `personalRecords`/`detectNewPrs` (derived from history — no
  stored ledger), per-exercise `ProgressStatus` (min-3-appearance gate + a
  meaningful-change threshold + best-of-window smoothing, so one off day can't
  flip a verdict), a per-muscle rollup (`normalizeMuscleGroup` folds free-text
  labels into six buckets), working-volume trend, an overall summary, typed
  `TrainingFinding`s (fact vs interpretation), and a `computeGoal`-based next
  step. **Warm-up sets are excluded everywhere.** Prefer this over the older
  per-day `analyzeDayProgress` (n=2) for progress questions.
- **Drill-down engine: `analytics/exercise_analysis.dart`** (`analyzeExercise`) — the
  per-exercise layer BENEATH the hub. Pure over `List<LiveSession>`; **reuses** the hub's
  primitives (`analyzeTraining` for the direction, `estimatedOneRepMax`, `isWorkingSet`,
  `computeGoal`) so hub and detail can't disagree, and adds what the hub can't show: full
  session-by-session records (sets/reps/load/volume/e1RM/avg-load/rep-range), consecutive
  `SessionComparison`s with typed `SessionChange` deltas, an **intensity-first**
  `ExerciseTrendTone` (e1RM leads, volume is secondary — a heavier-for-fewer-reps session
  can still be a win), PR-along-the-timeline flags, and a `CoachingInsight` (what
  happened → why → do) templated from the numbers. The pinned engine's numbers are
  untouched — this is purely additive (only new public export on `workout_analytics.dart`
  is `isWorkingSet`). **Mirrored in Node** (`functions/ai/exercise_analytics.js`) and fed
  to the AI coach via `get_exercise_analysis` + `get_training_analysis`'s `planAdherence`,
  pinned to the Dart engines by shared golden vectors (both suites run them).
- **Adherence engine: `analytics/plan_adherence.dart`** (`analyzePlanAdherence`) — joins
  the active plan against completed history (join key `PlannedExercise.id` ==
  `SessionExercise.exerciseId`) to flag **skipped** (planned, never trained) and **stale**
  (>14d) movements — the hub's "what's being skipped?" section.
- Import: `workout_import_input.dart` (the sealed `WorkoutImportInput` =
  `Document | Description`, mirroring diet), `workout_import_result.dart` (+
  `ImportedDay`/`ImportedExercise`), `workout_plan_from_import.dart` (takes a
  `source`), `workout_plan_normalize.dart`, `workout_plan_source.dart`
  (`manual`/`pdf`/`photo`/`dictated`/`typed`).

## Gotchas / invariants (don't re-litigate — see `docs/STATE.md` + git history)

- **The live session is read at arm's length, mid-set.** The session clock is 18pt and
  the segment captions 10.5pt for that reason (they were 13 and 9, which is decoration
  at a metre). The exercise name is capped at two lines so a long movement name can't
  push the goal card — the point of the screen — under the fold. Keep that bias when
  adding anything: if it can't be read without picking the phone up, it doesn't belong
  on this screen.
- **The docked music bar shows a reconnect, not nothing.** `SessionNowPlaying` collapses
  only on a device that has never linked to Spotify; a *linked* device that dropped mid-
  workout keeps a slim reconnect row, because the alternative was abandoning the session
  to go find Settings. See [`music/FEATURE.md`](../music/FEATURE.md).
- **Exercise-identity invariant** and the `splitId` alias are intentional; analysis/history
  are deliberately scoped to the **active** split.
- The splits-migration tie-break resolves to **oldest-by-`createdAt`** on purpose (matches
  `deleteSplit()` re-pointing).
- Home's Training card and the Workout page read the **same** `watchActivePlan()` →
  `plan.nextDay` source, so they stay in sync — don't add a separate Home workout source.
- **Training out of rotation defaults to a SWAP, not a skip.** `advanceToAfterDay`
  moves the recommendation past whatever was actually trained, so starting an
  out-of-order day costs the due day its turn. `showChangeWorkoutSheet` therefore
  carries a `ChangeWorkoutMode` toggle: **swap** (default) trades the two days'
  `order` via `WorkoutPlan.swapDays` *before* the session starts, so the
  displaced day comes up next and the cycle still covers every day exactly once;
  **skip** is the old drop-it behaviour. The cursor is not touched by a swap — it
  stores an `order`, so it keeps pointing at the same position. `slot` stays with
  its day (identity, not position — the editor's reorder doesn't reassign it
  either).
- **Never do calendar maths with `Duration`.** `Duration(days: 1)` is 24
  absolute hours; a calendar day on a DST transition is 23 or 25. Both old
  streak engines walked the calendar that way and zeroed themselves twice a
  year in `Africa/Cairo`. Use `core/util/calendar.dart`
  (`addCalendarDays`/`calendarDaysBetween`/`startOfWeek`), which is DST-proof by
  construction, and `test/core/calendar_test.dart` finds the ambient zone's
  real transitions to prove it.
- **One bucket instant: `completedAt ?? startedAt`.** Every engine uses it —
  `workout_analytics.dart`, `training_streak.dart`, `today_pulse.dart`,
  `functions/ai/workout_analytics.js`. `training_dashboard_stats.dart` was the
  lone holdout on `startedAt`, which is exactly how the hub and Today came to
  show two different streaks for the same history.
- **A restore is not a workout, and that is enforced by where it lives.** Streak
  restores are `TrainingDayMark`s in their own collection, never synthetic
  `LiveSession`s. As a session it would have to be filtered out of ~15 call
  sites and every one written afterwards; as its own collection the guarantee is
  structural. Don't "simplify" it into the session store.
- **A left-open session is closed at its last logged set, never capped.**
  `LiveSession.autoClose` ends at `lastActivityAt` (derived from
  `LoggedSet.resolvedAt`), or records `DurationSource.unknown` when there is no
  evidence to close at. A capped duration is a fabricated number that still
  lands in the average — the exact thing being protected against. Staleness
  needs BOTH past-the-maximum AND `kStaleInactivityGrace` of silence, so a real
  workout running long is never closed under someone mid-set.
- **Nothing about closing or correcting a session may touch a set.** `autoClose`,
  `finishEarly` and `correctDuration` leave pending sets pending — no reps, no
  load, not marked skipped. Every counter downstream already ignores a pending
  set, which is why "Finish now" was safe to add the moment there was a button
  for it. Regression-tested in `session_duration_test.dart` and
  `session_maintenance_test.dart`.
- **A session that recorded work is VOIDED, not deleted** (`SessionStatus.voided`
  + a `VoidReason`). It keeps its row in History and stops counting everywhere.
  Hard delete survives only for a session with no completed set — the same rule
  `LiveSessionController.leave` already applied. The asymmetry is the point:
  wrong data can be corrected, history cannot be curated.
- Import DTOs live under `workout/domain/` (moved off `ai/domain/`) — keep them here.
- **Warm-up and rest are the SAME screen — now literally one widget.** They were two
  builders the docs asked you to keep identical; they are `CountdownPhase`
  (`widgets/live_session/phases/`) rendered twice: eyebrow → ring → what's-coming card →
  ±15s → skip. A phase only chooses its hue (ember vs green), its words, and what its
  buttons do. Don't re-specialise one back into its own widget. (Music is NOT in this
  stack any more — see the persistent-session-bar bullet below.)
- **Both countdown phases pause from three places** — the eyebrow pill, the ring itself,
  and the header toggle — and while paused the whole phase is `IgnorePointer`'d, so the
  dimmed area doubles as the resume target (`paused-resume-overlay`). The pill used to
  *look* like a pause button while being inert decoration inside that dead region; that's
  the bug this arrangement fixes, so don't collapse it back to a single header control.
- The rest ring's numeral is centred by being the ring Stack's **only sizing child**; the
  hundredths hang off its right edge at zero layout width. Both type sizes are set against
  the *circle*, not against each other — at the original 74/26 the readout crossed the
  stroke. Covered by a geometry test; don't restore a mirrored spacer or bump the sizes.
- **The logging screen's spare height is split into TWO equal gaps** — one above the
  hero (goal card + steppers), one below it — in `RunningScaffold`. It used to be a single
  `Spacer` above, which dumped all the slack between the set chips and the goal card and
  left the reps/weight steppers welded to the commit row. The split also halves how far
  the screen moves when the music dock appears or disappears under it. Don't collapse it
  back to one gap.
- **The commit row is `kCommitRowHeight` (52), not the app's usual 60**, and
  `kCommitRowSpace` is what the scroll reserves for it. It is pinned over the content, so
  its height is height the steppers don't get — that's the whole reason it's smaller here.
- **The reps/weight cluster is one `TapRegion` group (`kSetInputGroup`).** iOS's decimal
  pad ships no Return key, so the fields cannot dismiss their own keyboard: a tap anywhere
  *outside* that group does it (`onTapOutside`), a downward drag on `PhaseScroll` does it
  (`keyboardDismissBehavior: onDrag`), and a `Done` pill (`dismiss-keyboard`) appears over
  the commit row while a field holds focus. The ± steppers and the quick-load chips are
  deliberately *inside* the group so adjusting a value doesn't yank the keyboard away.
  `RunningScaffold` detects focus with an inert `Focus` node, **not** `MediaQuery.viewInsets`
  — a resizing `Scaffold` strips that out of its own body.
- **The weight field carries the last load forward** (`LiveSessionController.carriedWeightFor`).
  `computeGoal` only prices a set when it has an index-aligned set from that exercise's
  history or a plan `targetWeightKg`; a split written without loads has neither, so the
  field was empty on every set forever. The fallback searches nearest-first — this session,
  the aligned set, any load in that history, the plan — and is scoped to the **same
  exercise**. It is a suggestion, not a draft: `_actualsTouched` stays false, so nothing is
  persisted until the set is committed.
- **`AnimatedSize` cannot be used inside a phase.** `PhaseScroll` wraps its column in
  `IntrinsicHeight` so the `Spacer`s can distribute slack; `AnimatedSize` reports its
  child's intrinsic height while laying out an animated one, so the column gets pinned
  short and overflows. Animate the *contents*, or hold the height fixed instead.
- The goal card is a **fixed height for a given set**, on purpose: the intra-session chip
  ("matching your previous set") is always rendered for every set after the first, changed
  or not. It used to appear only once you moved the weight, which resized the card under
  your thumb. Regression-tested via `Key('goal-card')`. (The card no longer carries a
  per-set volume line or a "% vs last" delta — those were dropped as redundant with the
  plain-language hint + the LAST TIME cell; keep it to one comparison voice.)
- The logging screen's commit row **floats over** the scroll area rather than splitting the
  height with it, so it is never below the fold; the scroll reserves `kCommitRowSpace` and
  fades into it. Below `minPinnableHeight` (a keyboard on a very short device) it falls
  back to scrolling everything — that fallback is what keeps the keyboard-overflow stress
  test green.
- **Music rides a single persistent bar for the whole session**, not a per-phase strip.
  `SessionNowPlaying` (density `SpotifyStripDensity.bar`) is docked as the last child of
  the top-level `Column` in `build` — OUTSIDE the phase `AnimatedSwitcher` — so it stays
  put (no fade/reflow) across warm-up, logging, and rest, and carries the full
  prev/play-pause/next transport in every phase. The point is to change a track without
  leaving for Spotify or scrolling to find a strip. It collapses to nothing when no track
  is connected (no connect-nag; connecting lives on Today / the full player). Don't re-add
  the old per-phase strips (the `inline`/`rest` densities inside the phase scrolls).
  Regression-tested by "the music companion is docked in EVERY phase".
