# hub — feature map

> The Hub tab: a calm launcher into the app's modules, in the app's own
> material language — compact area rows carrying a live stat, plus one
> intentional hero image for Sleep.

## Start here

- `presentation/hub_page.dart` — the whole feature (single file). A grouped
  **areas card** (Workout · Diet · Expenses · Moments), then the full-width
  **Sleep hero** (a painted night sky), then the **Connected** band (Spotify ·
  Google Drive). Area rows route into the feature pages; the Connected rows
  route into Settings / Storage & sync.

## Design

- **Area rows** (`_ModuleRow`, composed in `_AreasCard`): the module's own
  photo as a small leading thumbnail (`_RowThumb`, `assets/hub/<x>.jpg`), the
  localized label, and a live mono stat *beneath* the label (so a long line like
  "Full arm (Day 4) · Up next" wraps within the row instead of fighting the
  chevron), then a trailing chevron. One grouped card with inset hairlines,
  like `TrainListCard` / Settings — compact rows, not the old oversized
  photo-topped grid.
- **The photo is the identity; the hue is the fallback.** `_RowThumb` falls back
  to a hue wash (Workout = green, Diet = green, Expenses = amber, Moments =
  ember — the four-hue system, ADR-006) only if an asset is ever missing, so
  keep new rows on that colour map.
- **Sleep hero** (`_SleepBand` → `_SleepHero`): the page's one image, a
  full-width nocturnal card. `_NightSkyPainter` draws it — a violet→indigo sky,
  a low violet aurora, a soft glowing moon, and a deterministic star field —
  in Sleep's own hue (the `glow` accent is `TrainColors.sleepGlyph`, ADR-010),
  in the same gradient language as the Sleep screen. Last night's **duration**
  is set large (mono) over a bottom legibility scrim, with the **method**
  beneath it — the method is never dropped (a bare figure is a claim ZIVO can't
  stand behind, `docs/SLEEP_SYSTEM.md` §11). No night yet → the empty copy in
  place of the figure. The hero is **always dark** — a night is a night — so its
  text is white for vibrancy, a deliberate single-look surface.
- **Connected band** (`_SpotifyRow` / `_DriveRow`): real brand marks on a
  neutral `_BrandTile`, **always at full colour** — the connection state lives
  in the trailing value, never by hiding/dimming the mark (a not-connected
  Spotify must still show the affordance to connect it).

## Gotchas

- Keep this a **thin launcher** — feature logic belongs in the feature, not
  here. Each `_XTile` only fetches; `_ModuleRow` / `_SleepHero` are
  presentation-only.
- The page is one `SingleChildScrollView` `Column` — no fixed grid — so no
  device height or text scale clips a module. Rows and the stat clamp to 1.4×
  text scale (covered by `test/hub/hub_page_test.dart`).
- Stat **strings** are asserted verbatim in the test (e.g. `0 OF 3 · 1270 KCAL`,
  `EGP 685 THIS WEEK`, `1 MOMENT`) — change the wording and update the test.
- `assets/hub/<x>.jpg` feed the row thumbnails (declared under `assets/hub/` in
  `pubspec.yaml`). Sleep has no photo — it's the painted `_NightSkyPainter`.
