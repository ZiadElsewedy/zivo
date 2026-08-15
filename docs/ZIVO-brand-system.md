# ZIVO — Brand System

Paste this whole file into Claude (or drop it in a repo as `BRAND.md`) before asking for any ZIVO screen or asset. It is the complete visual contract.

---

## v2.0 — Light & Warm (CURRENT direction — supersedes the v1 sections below where they conflict)

> After reviewing the first screens, the dark/mono/austere v1 skin read as cold and "developer-tool."
> ZIVO's actual feel is **light, warm, energetic, alive — with soul.** v2 keeps v1's structure,
> logo, 5-hue *meaning* system, spacing rhythm, motion identity, and layout rules, and changes the
> **surface mode, typography, and a few restraint rules**. Where v2 and v1 disagree, **v2 wins.**

**Mode.** Light is the primary (and, for now, only) mode. Dark may return later as an option.

**Ground & surfaces (light):**
| Token | Hex | Use |
|---|---|---|
| Ground | `#F6F4EF` | app background (a picked warm off-white — **not** stark white, **not** cream) |
| Card | `#FFFFFF` | cards, sheets — bright, lifted |
| Ink | `#1D1A16` | primary text (warm near-black) |
| Ink-2 | `#6B655C` | secondary text |
| Ink-3 | `#A49E93` | muted / tertiary |
| Hairline | `rgba(29,26,22,0.09)` | separators |

**Soft shadow returns (v1 banned shadows — v2 allows them, gently).** Depth/warmth comes from bright
cards lifting off the warm ground on soft, warm-tinted shadows: `0 2px 4px rgba(60,45,30,0.04),
0 14px 30px -16px rgba(60,45,30,0.22)`. This is a primary source of "alive."

**Hues, light-tuned** (dot = vivid, text = legible on white). Meanings unchanged from v1:
| Token | Dot/fill | Text | Meaning |
|---|---|---|---|
| Ember | `#FF5A1F` | `#DC490E` | now / next / primary action |
| Pulse | `#12C48A` | `#0A8F63` | training / health |
| Solar | `#F6B300` | `#A9760A` | money / expenses |
| Iris | `#6E5BFF` | `#5B49E6` | university / study / focus |
| Flare | `#FF3D6E` | `#DE2C56` | overdue / alert |

**Colour on surfaces is now allowed as a whisper** (v1 said colour only on text/dots). A section
card may carry a **soft hue wash** of its area (e.g. Now/Next `#FFF3EB`, Training `#ECFBF4`) to add
warmth. Keep it a wash, never saturated; the one-hue-per-region and **Ember-appears-once** rules
still hold. Total saturated colour still stays low.

**Typography (replaces v1's Sora/Geist/Geist Mono/Instrument Serif entirely):**
| Role | Family | Weights | Use |
|---|---|---|---|
| Display | **Bricolage Grotesque** | 600, 700 | greeting, screen & card titles, hero numbers |
| Text | **Hanken Grotesk** | 400, 500, 600, 700 | everything — rows, labels, buttons, **data/numbers** |
| Aside | **Fraunces** italic | 450, 500 | one warm line per screen (asides, empty states) |

- **No monospace.** Numbers/times/amounts use Hanken with `font-variant-numeric: tabular-nums`.
  Removing the mono was the single biggest fix for the "coding tool" feel.
- Uppercase micro-labels are Hanken 600 with ~0.11em tracking (not a mono, not all-caps mono).
- All three families are OFL / on Google Fonts.

**Radius (slightly friendlier than v1):** cards/sheets **18–20**, chips/inputs 8, buttons/dots 999.

**Voice (loosened from v1's clipped tone).** Still short and second-person, but allowed a little
warmth and rhythm — a dash, a human beat. "Morning, Ziad ☀ — one deadline today, and a push session
waiting" over "Good morning. One deadline. Push day." No hype, no exclamation-spam, no emoji-noise
(one warm glyph like ☀ is fine, sparingly).

**Avoid the AI-generic warm look:** never let it collapse into "cream ground + serif display + a
single terracotta accent." The grotesque display, the full multi-hue palette (green/gold/iris/pink,
not just ember), and the non-cream ground are what keep ZIVO distinct.

Everything not restated above (logo, geometry, iconography grid & 2px stroke, spacing 4pt scale,
motion `cubic-bezier(0.2,0.8,0.2,1)` + 8° lean, component anatomy, the "never" list) **carries over
from v1 unchanged.**

---

## v1.0 — Dark (archived — superseded by v2 above; kept for the logo, geometry & rules v2 reuses)

## 1. Product

ZIVO is a **private personal operating system** — one app holding schedule, tasks, workouts, expenses, university, moments and notes. Ziad + *vivo* ("I live"). Intelligence sits underneath, never announces itself.

Feel: premium, minimal, calm, energetic, timeless. Not a productivity SaaS. No social features, no streaks, no applause.

Principles
1. Negative space is the brand — if it can be removed, remove it.
2. Colour is meaning, never decoration.
3. Hierarchy comes from type size and weight, not panels and borders.
4. The AI is invisible: no sparkles, no chat bubble as hero.

## 2. Logo — "Lean Aperture"

A rounded square tile with the letter Z **cut out** of it (negative space), the Z pushed 8° forward. The tile is the icon; never place it inside another container.

Primary asset — Lean tile, 100×100 viewBox, `fill-rule="evenodd"`:

```svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path fill-rule="evenodd" fill="currentColor"
    d="M22,0 H78 A22,22 0 0 1 100,22 V78 A22,22 0 0 1 78,100 H22 A22,22 0 0 1 0,78 V22 A22,22 0 0 1 22,0 Z
       M33,30 L75,30 L45,58 L67,58 L67,70 L25,70 L55,42 L33,42 Z"/>
</svg>
```

Solid Z (for use on coloured tiles, print, stamps):

```svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path fill="currentColor" d="M33,30 L75,30 L45,58 L67,58 L67,70 L25,70 L55,42 L33,42 Z"/>
</svg>
```

Line Z (in-app header/nav only — never the app icon):

```svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path d="M30,33 H74 L26,67 H70" fill="none" stroke="currentColor"
        stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

Upright tile (archive only — legal, embroidery, sub-16px): same outer path, inner `M30,30 L70,30 L44,58 L70,58 L70,70 L30,70 L56,42 L30,42 Z`.

Geometry
| Spec | Value |
|---|---|
| Tile corner radius | 22% of width |
| Z bounding box | 42%, centred |
| Bar height | 12% of tile |
| Lean | 8° forward |
| Diagonal | 47° |
| Clear space | 25% of tile width, all sides |
| Min tile | 16px |
| Min lockup | 88px wide |

Colourways only: ink on paper, paper on ink, ink on Ember, Ember on ink.

Lockup: tile + wordmark, gap = Z bar height. Wordmark is **Sora 600**, tracking 0.05em at 46px, 0.10em at 26px, 0.14em below 18px. Stacked variant allowed (tile above, wordmark below).

## 3. Colour

Surfaces (dark is the default mode)
| Token | Hex | Use |
|---|---|---|
| Void | `#07080A` | app background |
| Base | `#0B0D10` | cards, sheets |
| Raised | `#101317` | headers, tab bar, inputs |
| Muted | `#6E747A` | tertiary text, disabled |
| Second | `#9AA0A6` | secondary text |
| Paper | `#F4F2ED` | primary text on dark; light-mode background `#FBFAF7` |

Hues — each owns one area of life
| Token | Hex | Meaning |
|---|---|---|
| Ember | `#FF5A1F` | now / next / primary action |
| Iris | `#6E5BFF` | university / study / focus |
| Pulse | `#12E29A` | training / health |
| Solar | `#FFC02E` | money / expenses / budget |
| Flare | `#FF3D6E` | overdue / over budget / alert |

Rules
- **One hue owns one screen.** Training is Pulse throughout; expenses is Solar. Never mix hues in one screen region.
- **Ember overrides everything** and appears once per screen, on what happens next.
- Colour goes on text, dots and fills — **not on containers**. Cards stay Base/Raised.
- Under 8% of a screen's pixels are coloured.
- No gradients except one 12%-opacity hue wash behind the splash mark.
- On dark, tint Iris to `#8B7BFF` for text. On light, shade Ember/Solar 12% darker (Ember → `#D6410C`), Pulse 20% darker; Iris and Flare hold.

## 4. Type

| Role | Family | Weights | Use |
|---|---|---|---|
| Display | **Sora** | 600, 700 | wordmark, screen titles, hero numbers. Never below 20px |
| Interface | **Geist** | 400, 500, 600 | rows, labels, buttons, notes. Never above 28px |
| Data | **Geist Mono** | 400, 500 | times, amounts, reps, dates, caps labels |
| Aside | **Instrument Serif** italic | 400 | one quiet line per screen: empty states, asides |

All four are SIL Open Font License, on Google Fonts.

Scale
| Token | Spec | Example |
|---|---|---|
| D1 | Sora 600, 44 / 1.05, −0.04em | screen title |
| D2 | Sora 600, 28 / 1.15, −0.035em | section title |
| D3 | Sora 600, 34, −0.03em | hero number (unit at 18px, Muted) |
| B1 | Geist 500, 17 / 1.45 | list row primary |
| B2 | Geist 400, 15 / 1.55, Second | supporting text |
| L1 | Geist Mono 500, 12, 0.14em, caps | section labels, data |
| Q1 | Instrument Serif italic, 24 | aside |

## 5. Foundations

Spacing — 4pt base: `4` hairline · `8` icon-to-label · `12` inside rows · `16` row-to-row · `24` screen padding · `40` section break.

Radius: `6` chips/inputs · `12` cards/sheets · `999` buttons/dots · `22%` the logo tile only.

Iconography: 24px grid, **2px stroke**, round caps and joins, geometric and open. Filled only for the active tab. No badges, no duotone, no decorative accents. Colour only when the icon carries a hue's meaning. Minimum touch target 44px.

Motion: tap 90ms · sheet/push 240ms · splash mark 420ms · easing `cubic-bezier(0.2,0.8,0.2,1)`. Everything enters along the lean angle — up and to the right, 8°. Nothing bounces; nothing fades slowly. Brisk, then still.

Elevation: no shadows. Depth comes from surface steps (Void → Base → Raised) and 1px `rgba(255,255,255,0.08)` hairlines.

## 6. Components

- **Primary button** — Ember fill, `#0B0C0D` text, Geist 600 15px, padding 13/24, radius 999.
- **Secondary** — Paper fill, ink text. **Tertiary** — 1px `rgba(255,255,255,0.18)` border, Paper text. **Quiet** — Second text, no container.
- **Chips** — hue at 13–16% opacity as background, hue text, Geist Mono 12px 0.08em caps, radius 6.
- **Input** — Raised fill, 1px `rgba(255,255,255,0.1)`, radius 6, 15px; focused border becomes Ember with an Ember caret.
- **Card** — Raised on Void, radius 12, 1px hairline, padding 22/24. Header row: hue dot (7px) + Mono caps hue label + Mono time right-aligned; then D2 title; then B2 detail.
- **List row** — 7px dot (hue, or `rgba(255,255,255,0.2)` when inert) + B1 label + Mono value right-aligned, separated by hairlines, 15px vertical padding.
- **Tab bar** — Raised, 4 icons, active in Ember, inactive `#4A5057`.
- **Splash** — Void, Lean tile centred at ~74px, 12% Ember radial wash behind it, wordmark in Sora 600 11px 0.22em at the bottom in `#4A4F55`.

## 7. Voice

Short sentences. Present tense. Second person. State the fact, then stop.
No encouragement, no exclamation marks, no emoji, no "let's".

Good: "Saturday looks light. Two things matter." / "Moved from Thursday." / "The rest of the day is yours."
Bad: "You've got this! 3 tasks to crush today 🎯"

## 8. Never

- Rotate, stretch, or outline the tile.
- Add a glow, shadow, or gradient to the mark.
- Nest the tile inside another shape.
- Set the wordmark in anything but Sora 600.
- Use two hues in one screen region.
- Use the Line Z as the app icon.
- Add a sixth colour.
