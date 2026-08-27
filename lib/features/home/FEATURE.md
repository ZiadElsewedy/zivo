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
