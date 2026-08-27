# hub — feature map

> The Hub tab: a launcher for the app's modules (where feature tiles live/go live).

## Start here

- `presentation/hub_page.dart` — the whole feature (single file). Tiles route into the
  feature pages (workout, diet, expenses, moments, music, etc.).

## Gotchas

- Tile hues follow area ownership (Workout/Diet = pulse, Expenses = solar, Moments = ember);
  keep new tiles on the design system's hue map — see [`docs/ZIVO-brand-system.md`](../../../docs/ZIVO-brand-system.md).
- Keep this a thin launcher — feature logic belongs in the feature, not here.
