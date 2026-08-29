# workout — feature map

> The largest feature (~73 files). Splits, live guided sessions, progression analysis,
> body-weight tracking, and AI PDF plan import. Deep doc: [`docs/WORKOUT_SYSTEM.md`](../../../docs/WORKOUT_SYSTEM.md).

## Start here (entry pages — `presentation/pages/`)

| Page | Role |
|---|---|
| `workout_dashboard_page.dart` | Main workout surface / interactive dashboard |
| `workout_plan_page.dart`, `workout_plan_edit_page.dart` | View / edit the active split's plan |
| `split_management_page.dart` | Create / switch / edit / delete splits (multi-split) |
| `live_session_page.dart` | The guided live workout session (logging sets in real time) |
| `session_details_page.dart`, `workout_history_page.dart` | Past sessions + history |
| `workout_analysis_page.dart`, `workout_progress_page.dart`, `workout_stats_pages.dart` | Progressive-overload analysis, scoped to the active split |
| `workout_pdf_import_page.dart` | AI PDF import → review UI (pairs with `functions/ai/workout_import.js`) |
| `bodyweight_history_page.dart` | Body-weight log + trend |
| `workout_capture_page.dart`, `workout_day_details_page.dart` | Quick capture + day drill-in |

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
- The rest ring's numeral is centred by a **mirrored invisible spacer** left of it, sized
  to the hundredths slot on its right — that's what puts the big digits on the ring's true
  centre. Covered by a geometry test; don't "simplify" the spacer away.
