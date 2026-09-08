# ADR-011 — Light mode: one design system, two skins

**Status:** accepted · 2026-09-08
**Supersedes in part:** [ADR-006](ADR-006-one-design-system.md) ("one dark
system, app-wide" — the *one system* half stands; the *dark* half does not)
**Context:** [`lib/core/theme/zivo_palette.dart`](../../lib/core/theme/zivo_palette.dart) ·
[`lib/core/theme/train_tokens.dart`](../../lib/core/theme/train_tokens.dart)

## Context

ZIVO shipped dark-only. ADR-006 collapsed two competing palettes into one —
`TrainColors`, a class of `static const` colours — and the app has been read by
name off that class ever since: **1,677 references across 144 files**, plus 247
raw `Color(0x…)` literals in feature code that never went through it at all.

A gym floor at 6am and a bright room at noon are different rooms, and the app
was legible in one of them. Adding the other means every one of those ~1,900
colour reads has to be able to answer differently.

Two shapes were on the table.

**A `ThemeExtension`, resolved per `BuildContext`.** The idiomatic Flutter
answer: `context.zivo.ink`, with `lerp` for free and per-subtree overrides
possible. It also means rewriting all 1,677 call sites and threading a
`BuildContext` into the painters, `TextStyle` builders and helper functions
that currently have none — weeks of mechanical edits across nearly every
screen in the app, landing as one unreviewable diff.

**A swapped active palette.** The values move into a `ZivoPalette` instance,
`TrainColors` keeps its exact public API and becomes getters over whichever
instance is active, and the root swaps that instance. Measured before
committing to it: **244 compiler-flagged errors and one static capture** — the
whole cost, enumerated by the analyzer, with nothing silent in it.

## Decision

**1. `ZivoPalette` holds the values; `TrainColors` stays the name.** Two
immutable instances, `dark` and `light`. `dark` is the palette that shipped,
value for value — `zivo_palette_test.dart` pins the load-bearing ones, because
a change nobody asked for is a regression even when it is prettier.

**2. The active palette is process-wide, and the root is the only thing that
sets it.** `ZivoTheme.use(brightness)` is called in the builder that wraps
`MaterialApp`, above every route.

**And swapping it repaints the app, explicitly.** This is the part the first
cut got wrong, and it is worth stating plainly because it is not obvious:
nothing in the tree is *subscribed* to the palette — that is the whole point
of reading tokens by name — so rebuilding the root does not reach the screens.
`Element.updateChild` returns early for any child whose widget compares equal
to the one it already has, and every `const` widget does. `home: const
AuthGate()` alone stopped the rebuild at the first element under
`MaterialApp`. The app switched to light, and every screen that was already
built stayed dark; screens came out right only where a stream tick or a
freshly pushed route happened to rebuild them anyway, which is why Settings
looked correct and Today, Hub and You did not.

So `ZivoTheme.use` marks the whole tree dirty from
`WidgetsBinding.instance.rootElement` when the skin actually changes. It runs
in a post-frame callback, because `markNeedsBuild` on an element that has
already built in the current frame is an error — one stale frame, against a
screen that would otherwise stay wrong indefinitely. `MaterialApp` also gets
`themeAnimationDuration: Duration.zero`, since a 200ms `ThemeData` lerp under
tokens that snap just spends those 200ms showing half of each skin.

*What this forbids:* **never cache a token.** Not in a field, not in a
`static final`, not in `initState`. A `static` field is evaluated once and
would pin the app to whichever skin it first drew — which is exactly why
`AppText`'s ladder is getters now, and why the one `static const _neutralTile`
in the capture sheet became one. It also means a widget test cannot render
both skins in the same pump; a test that wants a skin calls `ZivoTheme.use`
and puts it back in `tearDown`.

*What it costs:* no `lerp`, so switching skins is a cut rather than a
cross-fade; and 206 widget expressions lost their `const` keyword, because a
getter is not a constant. Where the constant was a *parameter default*
(`this.color = TrainColors.ember`) the field became private and nullable with
a resolved getter over it, so those 30 constructors stay `const`.

**3. The light skin is not the dark one inverted.** Three rules keep them one
system rather than two:

* **Hue ownership survives; luminance does not.** Green is still state, ember
  still the one committing action, amber still money, violet still
  system/meta (ADR-006 §2). Each walks down until it holds up on paper.
* **Ink ramps are not mirrored alphas.** White-on-black stays legible much
  further down the ramp than black-on-white, so light's secondary/tertiary
  inks sit at .62/.55/.42 where dark's sit at .45/.40/.32.
* **Elevation is still light, not shadow** — which on paper means a raised
  surface *is* white, and the step above it goes grey. That is the one place
  the two skins move in opposite directions, and why `lift` exists.

**4. Contrast is a test, not a taste.** `zivo_palette_test.dart` holds the
light skin to WCAG: primary and secondary ink at 4.5:1 on the base, every hue
at 3:1, and every near-white label at 4.5:1 on the fill it labels. The first
draft of this palette failed that last one — green was at 3.4:1 — which is the
argument for the test in one line.

**5. The choice is device-local and defaults to dark.** `ThemeController`
mirrors `LocaleController` exactly: a `ValueNotifier` over
`SharedPreferences`, no state-management package, and nothing synced. Which
room you are in is a property of the phone, not the account. It defaults to
`ThemeMode.dark` rather than `ThemeMode.system` because the near-black is part
of the identity, and a new setting should be an offer rather than a silent
re-skin of every existing install on update day. Changing that is a one-line
change to `ThemeController.defaultMode` if the owner decides otherwise.

**6. Some surfaces keep one dressing in both skins, on purpose.** The Today
session slab (a saturated hero card is how "one hero per screen" reads on
paper too), the full-bleed photo viewer, the white flash of a completed set,
black scrims and shadows, and other companies' brand marks. These are the only
places a raw literal is still allowed outside `core/theme/`, and each one
carries a comment saying which case it is.

## Consequences

* Colour work still happens in one file, and screens still say
  `TrainColors.ink` — the seam ADR-006 built did not move, it just got a
  second set of values behind it.
* **A new colour must be added to both skins.** `ZivoPalette`'s constructor
  requires every field, so this is a compile error rather than a review catch.
* The 247 raw literals in feature code are down to 30 deliberate ones. That
  sweep was overdue under ADR-006 on its own; light mode is what made it
  urgent, because a literal cannot flip.
* `flutter analyze` is the safety net for the caching rule only at the point
  where a `const` breaks. A `static final Color x = TrainColors.ink` compiles
  fine and is silently wrong. The tests are the real net: `light_mode_smoke_test`
  builds each screen **in dark and then switches to light**, which is the
  sequence the app goes through and the only one in which a cached skin or a
  skipped element shows up at all. Rendering straight into light hides both —
  the first version of that test did exactly that, and passed while the app
  was visibly broken.
* **A full rebuild on every skin change** is the standing cost of the global
  palette. It is a one-off, it preserves every `State` and the navigation
  stack, and it is imperceptible next to the swap itself — but it is the
  reason the swap cannot animate, and therefore the thing to weigh if
  context-resolved tokens are ever reconsidered.

## Not decided here

* **Whether to default to `system`.** Worth revisiting once there is any
  signal about how many users go looking for the setting.
* **`auth_page`'s `#FF3D6E` error flare** is a fifth hue and a standing
  ADR-006 violation. It survives this change untouched; it should either
  become a token or become ember.
* **White-on-ember on the dark skin** sits at ~3.0:1 — below AA for a 14px
  bold label. Light mode's ember was tuned to clear 4.5:1, so the two skins
  are now *unequal* on the app's most important control. Fixing dark means
  changing a colour that has shipped, which is the owner's call.
