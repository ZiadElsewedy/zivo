# hub — feature map

> The Hub tab: a launcher into the app's modules, dressed as a light dashboard —
> each module card carries a live stat read straight from that module's repo.

## Start here

- `presentation/hub_page.dart` — the whole feature (single file). A 2×2 grid of
  photographic module cards (Workout · Diet · Expenses · Moments) over the
  **Connected** band (Spotify · Google Drive). Cards route into the feature
  pages; the Connected rows route into Settings / Storage & sync.

## Design

- **Module cards** (`_ModuleCard`): a hero photograph up top — the module's own
  image from [`assets/hub/`](../../../assets/hub) — melting into the card body
  via a bottom fade, then a hue-tinted icon chip, the localized label, and the
  live stat. The photos are the primary identity; the icon chip echoes the
  area's owned hue.
- **Hues (icon chips):** Workout = green, Diet = green, Expenses = amber,
  Moments = ember — all inside the four-hue system, so the grid differentiates
  by **image and colour** without spending a hue on decoration (ADR-006). Keep
  new cards on this map.
- **The hero images are cropped in-source** so the app overlays its own
  localized label rather than the photo's baked-in title (l10n + accessibility).
  `_HeroPhoto` falls back to a hue wash if an asset is ever missing.
- **Connected band** (`_SpotifyRow` / `_DriveRow`): real brand marks on a
  neutral `_BrandTile`, **always at full colour** — the connection state lives
  in the trailing value, never by hiding/dimming the mark (a not-connected
  Spotify must still show the affordance to connect it).

## Gotchas

- Keep this a **thin launcher** — feature logic belongs in the feature, not
  here. Each `_XTile` only fetches; `_ModuleCard` is presentation-only.
- Card height is fixed by `childAspectRatio` with a flex-centred content block;
  label + stat are clamped to 1.3× text scale so a large accessibility scale
  can't overflow the card (covered by `test/hub/hub_page_test.dart`).
- Stat **strings** are asserted verbatim in the test (e.g. `0 OF 3 · 1270 KCAL`)
  — change the wording and update the test.
