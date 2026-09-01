# home — feature map

> The **Today** surface: a single reactive home for what's next, assembled from small
> "glance" widgets that each read a feature's repo. Design intent: [`docs/UX_BLUEPRINT.md`](../../../docs/UX_BLUEPRINT.md).

## Start here

- `presentation/pages/today_page.dart` — the Today page. Built per-frame so it can receive
  an `onOpenAsk` callback from the shell (switches to the Ask tab).
- `presentation/header_builder.dart` — the greeting/header.
- Glance widgets (`presentation/widgets/`): `today_pulse_card.dart`, `diet_glance.dart`,
  `spending_glance.dart`, `hue.dart` (per-area color), `common.dart`.
- `domain/today_pulse.dart` — the Today "pulse" model.

## Data sources

Today does **not** own repositories — each glance reads an existing feature repo via
`AppScope` (workout `watchActivePlan()`/`nextDay`, `diet`, `expenses`, `stepCounter` for
the Move ring). Keep it that way: Today composes, it doesn't duplicate feature logic.

## Gotchas

- The Training glance and the Workout page share the **same** `watchActivePlan()` source —
  don't introduce a separate Today workout source (they must stay in sync).
- The Move ring hides itself when there's no step sensor (`AppScope.stepCounter == null`).
- **The insights strip is judged against an injectable clock** (`InsightsSection.now`,
  threaded from `TodayPage.now`), because two `buildInsights` rules are hour-of-day rules —
  steps from 16:00, diet from 19:00. Read the wall clock here and the widget tests pass or
  fail depending on when they run; that is exactly what happened. Pin the hour in a test,
  and **don't** gate an assertion on `DateTime.now().hour` instead — that only proves the
  nudge is absent for most of the day. A test about a brand-new account also wants
  `InMemoryDietRepository.empty()`: the default constructor seeds a demo plan, which is
  enough for the evening diet nudge to fire on a user who has entered nothing.
