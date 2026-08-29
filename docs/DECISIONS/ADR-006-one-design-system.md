# ADR-006: One design system — `TrainColors` only, and categories carry no colour

**Status:** Accepted (2026-08-29)
**Date:** 2026-08-29
**Deciders:** Ziad (owner) · implementer
**Relates to:** [`docs/ZIVO-brand-system.md`](../ZIVO-brand-system.md) (the v2 brand doc this
supersedes for colour and elevation) · `assets/design_handoff_workout_tracking 2/IDENTITY.md`
(the binding spec) · the 2026-08-28/29 design audit (findings C1, C2, C3, H3).

---

> This ADR records **two standing design decisions** so no future agent has to rediscover them
> from git archaeology. Current implementation status lives in [`../STATE.md`](../STATE.md); the
> tokens live in [`../../lib/core/theme/train_tokens.dart`](../../lib/core/theme/train_tokens.dart);
> the expenses specifics live in
> [`../../lib/features/expenses/FEATURE.md`](../../lib/features/expenses/FEATURE.md).

## Context

ZIVO carried **two colour systems at once**.

`AppColors` / `AppShadows` were "Brand System v2": warm-charcoal surfaces (`#15110D` ground,
`#211A14` cards), a warm ink ramp, five hues (ember, pulse, solar, iris, flare), and soft
warm drop-shadows described in their own doc comment as *"a primary source of the 'alive'
feel"*.

`TrainColors` arrived later with the workout-tracking design handoff: a cooler, darker base
(`#080908`), four hues (green, ember, amber, violet), and **depth from light, not shadow**
(IDENTITY.md §5 — the only permitted shadows are the coloured glows under primary pills).
Its own header doc scoped it to "the eleven handoff screens", with everything else left on v2.

That split was not stable, for two reasons the audit made concrete:

1. **The two palettes met on single screens.** The ever-present nav island and the Ask
   composer were warm objects sitting on cool screens. On the flagship AI screen the
   composer's mic and cursor were iris `#6E5BFF` while ZIVO's own branding directly above was
   violet `#8F8BFF` — two different violets, one screen.
2. **The warmth was inherited, not chosen.** `AppText`'s default ink and `AppTheme`'s
   `scaffoldBackgroundColor` were v2 values, so *every* screen — the cool handoff ones
   included — got a warm cast unless it explicitly overrode them. A screen only looked cool
   where someone had remembered to make it so.

Separately, expense categories carried a `CategoryHue` picked from a five-swatch picker. Two
earlier decisions removed its reason to exist: every category gained a distinct stroked
Lucide glyph (the emoji removal, audit H3), and holding "one hue = one meaning" strictly
(audit C2, owner's ruling) made every money surface amber. The swatch a user chose then
rendered **nowhere**.

## Decision

### 1. `TrainColors` is the only palette. `AppColors` and `AppShadows` are deleted.

- Every surface in `lib/` — pages, sheets, dialogs, snackbars, shared widgets, and the
  foundational `app_theme.dart` / `app_typography.dart` defaults — dresses from
  `TrainColors`. Both v2 files are **removed from the repo**, so there is no second palette
  to fall back to and no way to reintroduce the split by accident.
- `TrainColors` gained the tokens the handoff palette lacked for floating chrome: `raised`,
  `raisedStrong`, `hairlineStrong`, `tabInactive`, `neutralMark`, and the
  `ember`/`violet`/`green`/`amber` washes.
- **There is no fifth hue.** v2's `flare` (a red for alert/destructive) maps to **ember**,
  which already owns "the live/now marker, the single committing action, and the thing worth
  noticing". This is why `ZHue.flare` was removed and why a delete-proposal card is ember,
  not red.
- **Elevation is light, not shadow.** `AppShadows.card` is gone everywhere. A raised surface
  is the base lifted toward white (`raised`, or the top-lit `cardGradient`), with a hairline
  edge. The only shadows are `TrainColors.actionGlow` under primary pills, plus the lift
  under genuinely floating objects (the nav island, the capture FAB).

### 2. An expense category is a label + an icon. It carries no colour.

- `CategoryHue`, the add-category sheet's COLOR section, the `hue` Firestore field, its
  `hue is string` rules clause, and `category_hue_colors.dart` are all **removed**.
- Categories differentiate by their stroked `CategoryIcon` glyph and their label. Amber says
  "this is money"; nothing else on an expense surface spends a hue.
- This is a **persisted schema change**. Documents written before it keep a `hue` field:
  nothing reads it and no rule validates it, so it sits inert until the doc is next
  rewritten. No migration is required.

## Consequences

- **The v2 brand doc is now partly historical.** [`ZIVO-brand-system.md`](../ZIVO-brand-system.md)
  still describes the five-hue, warm-surface, soft-shadow system. Its *meaning* rules
  (one hue owns one area, ember appears once, colour never decorates) survive and are the
  backbone of this ADR. Its *values* — the warm palette, the light-tuned hue table, the
  shadow-based elevation — no longer describe the app. Read it for intent, not for hex.
- **A rules deploy is required** before category creation works against the live backend.
  The deployed rule still demands `emoji` and `hue`; the client now writes `iconId` and
  neither of the others. Command (owner creds): `firebase deploy --only firestore:rules`.
  Until it runs, "Add category" is rejected with permission-denied.
- **The colour picker cannot come back without a surface first.** A picker that sets a value
  the app never renders is worse than no picker: it promises something the product does not
  keep. If a future category-detail or budgets view genuinely wants per-category colour,
  build the surface, *then* reintroduce the field — not the other way round.
- **Some warmth was intentional and is now gone.** The v2 system was explicitly warm — its
  own doc called its surfaces *"warm charcoal, not cold gray — a near-black with a warm (not
  blue) cast"*. Standardising on the handoff's cooler base is a real aesthetic change,
  accepted deliberately: the handoff is the binding spec, and one slightly cooler app beats
  two systems colliding on one screen.

## What future agents should follow

1. **If something needs a colour, it comes from `TrainColors`.** Do not add a second palette
   file, and do not reintroduce `AppColors`/`AppShadows`. If a token is missing, add it to
   `train_tokens.dart` with a doc comment saying what it means.
2. **A hue must mean its thing.** green = training/state · ember = the single committing
   action, the now/next marker, and the one thing worth noticing · amber = money, and nothing
   else · violet = system/meta. If a tile or row needs to be distinguished, use its **icon**
   (`TrainColors.neutralMark` for the tile) — never an accent colour picked for variety.
   Grids that colour their tiles for decoration are the specific mistake audit C2 removed.
3. **Do not add a red.** Destructive and alert states use ember. The four hues are the whole
   vocabulary.
4. **Do not add drop-shadows to cards.** Depth comes from light. `actionGlow` under a primary
   pill is the sanctioned exception.
5. **Never set both `color` and `gradient` on one `BoxDecoration`.** The gradient installs a
   shader that overrides `color` outright, so the fill you wrote is silently discarded — a
   translucent top-lit ramp then renders as *nearly invisible* rather than as a lifted
   surface. Bake the ramp into opaque stops instead. (Existing `color` + `gradient` pairs in
   the codebase are either mutually-exclusive ternaries or a nested `Border.all(color:)`;
   both are fine.)
6. **Don't run `dart format` on a directory.** The repo is not format-clean under the current
   toolchain: formatting `lib/` rewrites ~116 unrelated files and surfaces new lints. Format
   only the files you actually edited.
