# ADR-009: One type system — three families, and `train_tokens.dart` names all of them

**Status:** Accepted (2026-09-01)
**Date:** 2026-09-01
**Deciders:** Ziad (owner) · implementer
**Relates to:** [ADR-006](ADR-006-one-design-system.md) (did this for colour and left type
behind) · [`../ZIVO-brand-system.md`](../ZIVO-brand-system.md) (the v2 doc this supersedes for
typography) · [`../../lib/core/theme/app_typography.dart`](../../lib/core/theme/app_typography.dart) ·
[`../../lib/core/theme/train_tokens.dart`](../../lib/core/theme/train_tokens.dart)

---

## Context

ZIVO shipped **five typefaces across two unreconciled type systems.**

`AppText` was Brand System v2 — **Bricolage Grotesque** (display), **Hanken Grotesk** (text),
**Fraunces** italic (aside). Those three were chosen for v2's *Light & Warm* skin: a warm
off-white `#F6F4EF` ground, soft warm shadows, five light-tuned hues.

`TrainType` arrived with the workout design handoff — **Azeret Mono** (numbers, timers,
micro-captions), **Manrope** (UI), **Instrument Serif** italic (the assistant's voice) — for a
cool near-black `#080908` base meant to be read in a gym, mid-set, at arm's length.

[ADR-006](ADR-006-one-design-system.md) resolved this collision **for colour only**: it made
`TrainColors` the single palette and deleted `AppColors`/`AppShadows` outright. Typography was
not in scope, so the split survived a layer down, with four concrete consequences:

1. **Half the app's type was dressed for a deleted skin.** v2's faces were picked against a
   warm off-white ground that no longer exists. Bricolage Grotesque in particular is an
   editorial variable grotesque whose warm, deliberately-wonky personality was *correct* for
   v2 and reads off-key on near-black next to a technical mono.
2. **Fourteen files used both systems at once** — including the flagship
   `today_page.dart`, which switched from `TrainType.mono` at line 351 to `AppText.rowTitle`
   at line 633.
3. **Hanken Grotesk and Manrope were redundancy, not contrast.** Two humanist neutral sans in
   the same slot: indistinguishable at a glance, but with different x-heights and widths, so
   rows drifted subtly between screens. Full cost, no expressive payoff.
4. **The reserved serif rule was inverted in practice.** `train_tokens.dart` declared
   Instrument Serif "the ZIVO assistant's voice, and nothing else in the app." Actual usage:
   `TrainType.serif` at **1** call site, `AppText.aside` (Fraunces) at **24**. The face that
   was supposed to be rationed was invisible; the one doing the work was unowned.

Separately, v2's rule that *"removing the mono was the single biggest fix for the 'coding
tool' feel"* had already been reversed by the handoff (Azeret Mono for numeric data) without
the surrounding text stack being revisited — so the app carried both the anti-mono text system
and the mono.

## Decision

### 1. Three families, and only `train_tokens.dart` names one.

| Role | Family | Builder |
|---|---|---|
| Text, prose, titles, chrome | **Manrope** | `TrainType.ui` |
| Numbers, timers, micro-labels | **Azeret Mono** (tabular) | `TrainType.mono` / `TrainType.caption` |
| The assistant's voice, and the one quiet line per screen | **Instrument Serif** italic | `TrainType.serif` |

**Bricolage Grotesque, Hanken Grotesk and Fraunces are removed from the app.** `GoogleFonts` is
called in exactly one file. This mirrors ADR-006's shape for colour: one file owns the
vocabulary, everything else spends it.

### 2. `AppText` survives — as a ladder, not as a system.

`AppText` is **not** deleted, and its ~500 call sites are untouched. It is re-implemented on
top of the three builders above. The reasoning is that the two APIs are answering different
questions and both answers are right:

- `AppText.rowTitle` names **what a thing is**. That is the correct API for prose and chrome,
  which want a small fixed ladder of semantic steps.
- `TrainType.mono(size: 54, …)` names **a size**. That is the correct API for the handoff's
  numeric surfaces, which specify a size per element rather than a ladder — pinning named
  steps there would just make every call site fight them.

Migrating `AppText`'s call sites onto `TrainType` builders was considered and rejected: it
would turn `AppText.rowTitle` into
`TrainType.ui(size: 16.5, weight: FontWeight.w500, height: 1.3)` at 86 sites, trading a
semantic name for a magic number and inviting exactly the drift the ladder prevents. **Two
APIs over one type system is the goal; two type systems was the bug.**

### 3. The style-by-style mapping, and the four deliberate changes.

Sizes, line heights and colours are carried over unchanged. Letter-spacing was converted from
absolute px to `TrainType`'s ems (`-0.68px @ 34px` → `-0.02em`) — the same value, expressed the
way the builders take it. Four things did change on purpose:

- **Display goes up one weight.** `greeting` w700→w800, `cardTitle` w600→w700. Bricolage's
  display weights carried more presence than Manrope's at the same number; this holds the
  hierarchy that existed.
- **`body` goes w400→w500.** It runs at 45% ink (`ink2`) on a near-black ground, where
  Manrope's Regular is thinner than Hanken's was. w500 restores the old density.
- **`heroNumber` and `amount` become mono.** They are numbers. `heroNumber` adopts the house
  hero pattern already set by `rest_ring.dart` and `goal_block.dart` — large, **light**
  (w300), tight negative tracking — so the expense keypad and the rest ring finally agree.
  Tabular figures stop a hero numeral reflowing as digits are typed or a timer counts.
- **`aside` becomes Instrument Serif.** This is the fix for the inverted rule above: the
  per-screen quiet line and ZIVO's own greeting (the Ask empty state's "Hey, I'm ZIVO.") are
  now one voice, in the face that was reserved for it. Note the assistant's *streamed replies*
  are sans and stay that way — that is a pre-existing choice this ADR does not touch.

`sectionLabel`, `hueLabel` and `tabLabel` become `TrainType.caption` — the handoff's existing
"9–12px mono, uppercase, wide tracking" pattern, which is what they already were in every
respect but the family. They inherit `caption`'s `height: 1`, which tightens their line box by
1–2px; this matches the 42 existing caption call sites.

`AppText.dateLabel` was **dead** (defined, never used) and is deleted.

## Consequences

- **`ZIVO-brand-system.md` is now fully historical for the visual layer.** ADR-006 took its
  colour, surfaces and elevation; this takes its typography. What survives is the *meaning*
  system (one hue per area, ember once, colour never decorates), the logo, geometry, spacing
  rhythm, motion identity, and the voice/tone guidance. Read it for intent; take type from
  `train_tokens.dart` and hex from `TrainColors`.
- **v2's "no monospace" rule is formally dead.** It was already contradicted in practice. The
  scope that replaces it: mono for **numbers and micro-labels only, never prose**. The
  "coding tool" feel v2 was guarding against comes from mono *body text*, which the app does
  not have.
- **`AppText.meta` stays Manrope, not mono, despite carrying tabular figures.** Its 170 call
  sites are overwhelmingly prose — error strings, "Forgot password?", "Password updated." It
  is a small-secondary-text style that happens to want tabular figures, not a numeric style.
  Moving it to mono would have been the single largest layout risk in this change for no
  design gain.
- **Cold-start cost drops.** Nothing is bundled in `pubspec.yaml`, so `google_fonts` fetches
  at runtime and caches; the first launch shows fallback text and reflows. Five families
  become three. **Bundling the three as assets would remove the reflow entirely and is the
  obvious follow-up — it is not done here.**
- **This is a visual change, not a refactor.** Every screen's type is re-dressed. It is
  deliberate, and it is the point: the app now looks like one product.

## What future agents should follow

1. **Three families. Do not add a fourth**, and do not call `GoogleFonts` outside
   `train_tokens.dart`. If a surface needs type it comes from `TrainType` or `AppText`.
2. **Reach for `AppText` for prose and chrome; reach for `TrainType` for numbers.** If you
   find yourself writing `TrainType.ui(size: …)` for a row title, the ladder already has a
   step for it.
3. **Mono means "this is a number."** Never set prose in Azeret Mono.
4. **The italic serif is ZIVO speaking.** Not a section header, not a marketing line, not a
   headline that isn't the assistant. Spending it elsewhere is spending the distinction.
5. **Weight, not a new face, is how you get emphasis.** Manrope runs 200–800; that range is
   the whole display vocabulary.
