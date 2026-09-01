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
| `workout_analysis_page.dart`, `workout_progress_page.dart`, `workout_stats_pages.dart` | Progressive-overload analysis, scoped to the active split |
| `workout_pdf_import_page.dart` | AI PDF import → review UI (pairs with `functions/ai/workout_import.js`) |
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

Each has `firestore_*` + `in_memory_*` impls in `data/`, wired in
[`lib/app/app.dart`](../../app/app.dart), exposed via `AppScope` (`workouts`,
`workoutPlans`, `workoutSessions`, `bodyWeight`).

## Domain highlights (`domain/`)

- Plan model: `workout_plan.dart` → `workout_day.dart` → `planned_exercise.dart`, with
  `exercise.dart`, `muscle_group.dart`, `rep_target.dart`, `rest_policy.dart`, `set_type.dart`.
- Live session: `live_session.dart`, `session_exercise.dart`, `set_log.dart`,
  `session_phase.dart`, `session_status.dart`, and `live_session_to_workout_log.dart`.
- Progression/analysis: `progression.dart`, `day_progress_analysis.dart`,
  `progress_comparison.dart`, `weight_trend.dart`, `up_next_selection.dart`,
  `training_dashboard_stats.dart`.
- Import: `workout_import_result.dart` (+ `ImportedDay`/`ImportedExercise`),
  `workout_plan_from_import.dart`, `workout_plan_normalize.dart`, `workout_plan_source.dart`.

## Gotchas / invariants (don't re-litigate — see `docs/STATE.md` + git history)

- **Exercise-identity invariant** and the `splitId` alias are intentional; analysis/history
  are deliberately scoped to the **active** split.
- The splits-migration tie-break resolves to **oldest-by-`createdAt`** on purpose (matches
  `deleteSplit()` re-pointing).
- Home's Training card and the Workout page read the **same** `watchActivePlan()` →
  `plan.nextDay` source, so they stay in sync — don't add a separate Home workout source.
- Import DTOs live under `workout/domain/` (moved off `ai/domain/`) — keep them here.
- **Warm-up and rest are deliberately the SAME screen** in `live_session_page.dart`
  (`_buildWarmup` / `_buildResting`): eyebrow → ring → what's-coming card → music strip →
  ±15s → skip. Only the hue differs (ember vs green). Don't re-specialise one of them.
- **Both countdown phases pause from three places** — the eyebrow pill, the ring itself,
  and the header toggle — and while paused the whole phase is `IgnorePointer`'d, so the
  dimmed area doubles as the resume target (`paused-resume-overlay`). The pill used to
  *look* like a pause button while being inert decoration inside that dead region; that's
  the bug this arrangement fixes, so don't collapse it back to a single header control.
- The rest ring's numeral is centred by being the ring Stack's **only sizing child**; the
  hundredths hang off its right edge at zero layout width. Both type sizes are set against
  the *circle*, not against each other — at the original 74/26 the readout crossed the
  stroke. Covered by a geometry test; don't restore a mirrored spacer or bump the sizes.
- **`AnimatedSize` cannot be used inside a phase.** `_phaseScroll` wraps its column in
  `IntrinsicHeight` so the `Spacer`s can distribute slack; `AnimatedSize` reports its
  child's intrinsic height while laying out an animated one, so the column gets pinned
  short and overflows. Animate the *contents*, or hold the height fixed instead.
- The goal card is a **fixed height for a given set**, on purpose: the comparison chip and
  the volume line are always rendered (the chip says "matching your previous set"; the
  volume line is a reserved 14px). They used to appear only once you moved the weight,
  which resized the card under your thumb. Regression-tested via `Key('goal-card')`.
- The logging screen's commit row **floats over** the scroll area rather than splitting the
  height with it, so it is never below the fold; the scroll reserves `_commitRowSpace` and
  fades into it. Below `minPinnableHeight` (a keyboard on a very short device) it falls
  back to scrolling everything — that fallback is what keeps the keyboard-overflow stress
  test green.
