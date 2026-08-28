# Prompt for Claude Code — Gym App: Workout Tracking (3 screens)

Paste this whole file into Claude Code, with `Workout Tracking.dc.html` in the repo (or alongside it) as the visual reference.

---

You are implementing three screens of an existing mobile gym-tracking app: **Today (home)**, **Active Set (logging)**, and **Rest**. A high-fidelity HTML prototype is provided in `design_handoff_workout_tracking/Workout Tracking.dc.html` — open it in a browser to see the intended look and live behavior.

**The HTML is a design reference, not code to copy.** Recreate it pixel-faithfully in this codebase's existing environment (React Native / Expo / SwiftUI / whatever is already here), using established components, navigation, and state patterns. If no environment exists yet, pick the most appropriate one and say why before you start.

Fidelity: **high**. Colors, type, sizes and spacing below are final — match them.

## Design intent (do not lose this in translation)
1. **One hero number per screen.** Rest = the countdown. Active Set = reps × weight. Today = the clock. Everything else drops to small mono captions. No competing large numbers.
2. **All numeric data is tabular monospace** (Azeret Mono, `font-variant-numeric: tabular-nums`, negative letter-spacing on large sizes) so running timers never shift width. Units and decimals are always smaller and dimmer than the value they belong to (e.g. `1:29` at 74px / `.46` at 26px).
3. **Ember orange `#FF5C1A` is reserved for the single committing action on a screen** (Start Workout, Log set) and the "current" marker. Green `#1FE08A` means state and progress (done, rest, on-track). Never use ember for decoration.
4. **Spotify is text-first — there is no album-art tile.** It's presented as instrumentation: a 3–4 bar animated equalizer glyph in green, the track title in the app's own UI font (Manrope 700), artist + timecodes in mono, a 2px progress hairline, and a small `SPOTIFY` mono label. This is deliberate: artwork competes with the metrics for attention.
5. Dark surface only. Depth comes from a single soft radial glow per screen plus 1px `rgba(255,255,255,.07)` hairlines — no drop shadows except the colored glow under primary buttons.

## Design tokens
```
bg base            #080908
bg tint (Today)    radial-gradient(120% 60% at 15% 0%, #12251c, #0a0b0a 55%, #080908)
bg tint (Set)      radial-gradient(120% 55% at 50% 100%, #1a0d06, #0a0908 60%, #080908)
bg tint (Rest)     radial-gradient(100% 50% at 50% 42%, #0d2b21, #0a0f0d 55%, #080908)
surface            rgba(255,255,255,.035) → .055 (gradient top-lit)
hairline           rgba(255,255,255,.07)
text               #F7F7F3   secondary rgba(244,244,240,.45)   tertiary rgba(244,244,240,.32)
green              #1FE08A   green dim rgba(31,224,138,.08) fill / .30 border
ember              #FF5C1A   ember fill rgba(255,92,26,.12) / border .35
session card       linear-gradient(155deg,#0f5f3f,#0a3a29 58%,#0b2a20)
radius             pill 99 · card 22–26 · chip 14–16
type UI            Manrope 400/500/600/700/800
type numeric       Azeret Mono 200/300/400/500/600
caption pattern    9–10px mono, letter-spacing .14–.24em, uppercase
screen padding     22px horizontal, 60px top (below status bar), 34px bottom safe area
primary button     60px tall, pill, box-shadow 0 12px 32px <accent>/.3
```

## Screen 1 — Today
Vertical stack, 22px gutters:
- Mono caption `THU 27 AUG` (10px, .18em). Clock `11:53` in Azeret Mono 300/54px, letter-spacing -.045em, with `PM` in 13px mono .4 opacity baseline-aligned. Greeting `Evening, Ziad` Manrope 800/27px, -.02em.
- Top-right: two 40px circular glass buttons (mic, do-not-disturb). DND is tinted violet `rgba(143,139,255,.1)` with `#a8a4ff` glyph when active.
- `TODAY` caption, then a 3-up metric card (radius 22, hairline border, top-lit gradient) split by 1px vertical dividers inset 18px. Each cell: 74px SVG progress ring (r=32, 3px stroke, round cap, rotated -90°, track `rgba(255,255,255,.07)`) with the value inside — icon for Trained (green ring, complete), `5.4` + `K` for Steps (white ring, ~69%), `7.2` + `T` for Volume (ember ring, ~81%). Below each: Manrope 700/12.5px label + mono 9.5px sub (`PULL · 62 MIN`, `OF 8K`, `+12% WoW`).
- `NEXT SESSION` / `WEEK 4 · DAY 2` caption row, then the session card (radius 26, green gradient above, green radial bloom top-right): green dot + `PULL` mono tag, `Change` outlined pill, title `Pull Day 1` Manrope 800/30px, then a 3-stat mono row (`10` EXERCISES · `24` SETS · `~65` MINUTES) divided by 1px rules, then the 56px ember `Start Workout` pill with play glyph.
- Bottom: Spotify strip (radius 20, surface): 4-bar equalizer, title Manrope 700/13px + artist mono 10.5px, pause + next glyphs, then a row of `elapsed · 2px progress · -remaining · SPOTIFY`.
- Tab bar: TODAY / HUB / ASK / YOU, 21px stroked icons + 8.5px mono labels; active tab ember.

## Screen 2 — Active Set
- Header: 36px circular close (left), centered `DAY 2 · PULL DAY 1` mono 9px .18em with session elapsed `1:35:28` mono 13px under it, 36px circular delete (right).
- Session progress: 10 equal 3px segments, gap 3px — completed green, current ember, remaining `rgba(255,255,255,.1)`. Under it `EXERCISE 4 / 10` and `07 SETS LOGGED`.
- `NOW` caption in ember, exercise name `Lat Pull Down` Manrope 800/34px -.03em, muscles mono `LATS · BICEPS · WIDE GRIP`.
- Two set chips side by side (SET 1 active = ember tint + ember border showing `8 × 45`; SET 2 inert showing `— × —`).
- Hero metric card (radius 24): left `GOAL` caption green + reps value Azeret Mono 300/62px with `REPS` unit; right weight Azeret Mono 300/42px + `KG` and a delta caption (`MATCHING LAST` dim / `↑ 2.5 KG VS LAST` green / `↓ … ` ember). Hairline, then a 3-up footer: LAST TIME `8 × 45 kg`, TARGET RANGE `8–10 reps` (green), RPE `8.0`.
- Two steppers (REPS, WEIGHT · KG): 52px tall, radius 16, 46px −/+ tap zones with hover tint, value centered in mono 20px. Reps step 1 (clamp 1–30), weight step 2.5 (clamp ≥0). Editing either updates the hero numbers and the SET 1 chip live.
- Spotify one-line strip (3-bar eq, title + artist inline, `-2:37`, next glyph).
- Footer: 112px `Skip` ghost pill + flexible ember `Log set` pill (60px, check glyph). Logging freezes SET 1's values, flips the label to `Logged`, bumps the logged-sets counter, and routes to Rest.

## Screen 3 — Rest
- Same header + segment bar (4 green, rest dim), right caption `SET LOGGED · 8 × 45` in green.
- Centered `REST` pill: green outline + `rgba(31,224,138,.08)` fill, pause glyph, mono 10px .2em.
- 290px ring: track r=132 7px `rgba(255,255,255,.07)`, progress green with `drop-shadow(0 0 12px rgba(31,224,138,.45))`, round cap, rotated -90°, `stroke-dasharray: 829.4`, offset = 829.4 × (1 − remaining/total). Behind it a radial green bloom pulsing 2.4s (scale 1→1.06, opacity .5→.15). Inside: `1:29` Azeret Mono 200/74px + `.46` 26px dim, then `OF 2:00 PLANNED` mono 9px .24em.
- `UP NEXT` card: `Seated Row · Wide Grip` Manrope 700/16px on the left, `10 × 40` mono 20px + `SET 1 · KG` on the right.
- Spotify strip with prev / pause (green) / next.
- `−15s` and `+15s` ghost pills (52px), then the 60px green `Skip rest` pill with dark `#04140d` label.

## Behavior
- Rest timer counts down at 60ms resolution and renders centiseconds; ring animates continuously from the same value (no CSS transition — drive it from state). ±15s clamps at 0 and raises `total` when it exceeds it so the ring stays ≤100%. Skip rest → next exercise's first set.
- Set flow: log set → set chip fills, counter increments, navigate to Rest with that set's numbers echoed in the header caption; on rest end (or skip) go to the next set/exercise.
- Spotify: position advances while playing, auto-advances to the next track at the end; next/prev reset position to 0; pause/play toggles the glyph and freezes the equalizer animation. Wire to the real Spotify Web/iOS SDK — prototype uses a local track list. Long titles truncate with ellipsis (or marquee on overflow); never wrap to two lines.
- All buttons: `scale(.985)` on press; ghost pills lighten to `rgba(255,255,255,.07)` on hover/press. Timers must keep running when the app is backgrounded (use a wall-clock timestamp diff, not an interval counter).
- Accessibility: every tap target ≥44px (the −/+ zones are 46×52). Announce rest countdown at 10s and 3s via haptics + optional audio cue.

## State
`restRemainingMs`, `restTotalMs`, `reps`, `weight`, `currentSetIndex`, `loggedSets[]`, `exerciseIndex`, `sessionStartedAt`, `spotify: { trackIndex, positionMs, playing }`.

## Out of scope
Onboarding, plan editing, the HUB/ASK/YOU tabs, history charts.
