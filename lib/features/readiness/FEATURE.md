# readiness — feature map

> The Daily Readiness call — one deterministic **train hard / go light / rest**
> recommendation, fused from data ZIVO already holds, each factor citing the
> number behind it. Decision + rationale:
> [ADR-015](../../../docs/DECISIONS/ADR-015-readiness.md).

## The one rule

Readiness is **derived, never stored**, and the gate returns null. It is
computed on the client from existing streams (like the sleep glance), and when
no signal is notable enough to cite a number — nothing to explain the call —
the engine returns null and the Today card hides. A call with a verdict but no
factor would break the feature's own rule; a fabricated call is a statement
about the user that isn't true.

## Start here

| File | What it is |
|---|---|
| `domain/readiness.dart` | the pure engine. `computeReadiness(...)` extracts signals from the domain objects and delegates to **`readinessFromSignals(...)`** — the primitive-level combination logic pinned to the Node coach mirror by shared golden vectors. Carries the thresholds, the verdict maths, and `readinessDeloadDue` (reads `analyzeTraining`'s verdicts — no new stall test) |
| `presentation/readiness_labels.dart` | the copy contract — verdict word/blurb/colour and each factor's icon/title/detail. Status colours only (green/amber/ember), no new hue |
| `presentation/widgets/readiness_glance.dart` | **`ReadinessSection`** — the Today card. Composes the same streams the other sections read; hides when the engine returns null. `ReadinessFactorRow` is shared with the detail page |
| `presentation/pages/readiness_page.dart` | the detail page — the call, every factor with its number, a "how it's worked out / what it isn't" note, and an optional "Ask ZIVO about this" route into the coach |

## Wiring

- **No repository** — the score is derived, so there is no `AppScope.readiness`.
  `ReadinessSection` reads `sleep` / `workoutSessions` / `bodyWeight` off
  `AppScope` directly.
- **Surfaced** on Today: `ReadinessSection` sits after `TodayPulseSection`,
  before the training card, in
  [`today_page.dart`](../home/presentation/pages/today_page.dart). `onOpenAsk`
  is threaded through so the detail page can switch to the Ask tab.
- **Coach (staged):** `functions/ai/readiness.js` (the Node mirror of
  `readinessFromSignals`, pinned by `test/fixtures/readiness_vectors.json`),
  the `get_readiness` read tool in `functions/ai/tools.js`, and a note in
  `functions/ai/chat/prompt/sections/training.js`. **Committed and offline-
  tested, but not live until `firebase deploy --only functions`.**
- **Steps groundwork:** `features/device/steps/step_day_repository.dart`
  (`StepDayRepository`, Firestore + in-memory) records
  `users/{uid}/stepDays/{yyyy-MM-dd}` from a throttled writer in
  [`app.dart`](../../app/app.dart). **Not read by readiness yet** — it accrues a
  step history for a later input (the sensor only exposes today's live count).

## Gotchas

- **It fuses, it never re-derives.** The deload signal is `analyzeTraining`'s
  verdicts, not a new stall test; sleep is `SleepNight`/`SleepTargets`; weight is
  `computeWeightTrend`. Don't reimplement any of them here.
- **`readinessFromSignals` is the pinned layer.** It takes primitives only (no
  domain objects, no other engines) so the Dart engine and the Node coach mirror
  stay identical via the shared vectors. Change the logic there, update the
  vectors, and keep BOTH suites green.
- **Sleep is only "last night" when it is.** The engine uses the newest night
  only if `SleepWindow.ageInDays <= 1`; an older night is dropped, never
  relabelled — the same claim the sleep glance is careful about.
- **Colour is status, not a hue.** green/amber/ember mean train-hard/go-light/
  rest. Readiness owns no colour of its own (ADR-006).
- **The card hides, it never shows a zero.** Same rule as the sleep glance — an
  absent card is a statement about the data; a rendered "rest" on no data would
  be a false statement about the user.
