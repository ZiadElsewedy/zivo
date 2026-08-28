# ZIVO — Visual Identity & Design Language

The binding spec for anything built in this app. If a decision isn't covered here, derive it from the seven principles.

---

## 1. Seven principles

1. **One hero number per screen.** Every screen has exactly one figure allowed to be large. Rest = the countdown. Active Set = reps × weight. Diet = kcal left. Player = the track title (type, not a number). Everything else demotes to captions. Two large numbers on one screen is a bug.
2. **Numbers are instruments.** All figures are tabular monospace with negative tracking at large sizes, so running values never shift width. Units and decimals are always smaller and dimmer than the value they belong to (`1:29` at 74px, `.46` at 26px, `KG` at 11px/35% opacity).
3. **Ember is a promise, not decoration.** `#FF5C1A` marks the single committing action on a screen (Start workout, Log set, primary FAB) and the "current" position marker. Nothing else. Green `#1FE08A` means state and progress — done, resting, on-track, connected. Amber `#e6be3c` is money only. Violet `#a8a4ff` is system/meta (theme, calendar, assistant chrome).
4. **Text over imagery.** No album art, no decorative photography, no illustration. The Spotify surfaces prove the rule: an animated equalizer glyph, the track set in the app's own UI type, and mono timecodes. Never render a container whose content is a placeholder waiting on data.
5. **Depth from light, not shadow.** One soft radial glow per screen tinted toward that screen's meaning, plus 1px `rgba(255,255,255,.07)` hairlines and top-lit surface gradients. The only shadows in the app are the colored glows under primary pills.
6. **Captions are mono, uppercase, wide.** 8.5–10px, letter-spacing .14–.24em, 28–40% opacity. They label; they never compete.
7. **Nothing shifts when something is absent.** Optional modules (music, heart rate, wearables) leave their slot to be reclaimed by data of equal usefulness — never by empty space or an inflated button. Music off is a first-class layout, not a degraded one.

## 2. Color

```
bg base              #080908
surface              rgba(255,255,255,.035) → .055   (linear-gradient 180deg, top-lit)
hairline             rgba(255,255,255,.07)
hairline strong      rgba(255,255,255,.12)

text primary         #F7F7F3     (#F9F9F5 on hero numerals)
text secondary       rgba(244,244,240,.45)
text tertiary        rgba(244,244,240,.32)

ember   #FF5C1A      fill rgba(255,92,26,.12)   border rgba(255,92,26,.35)   glow 0 12px 32px rgba(255,92,26,.32)
green   #1FE08A      fill rgba(31,224,138,.08)  border rgba(31,224,138,.30)  glow 0 12px 32px rgba(31,224,138,.25)
amber   #e6be3c      fill rgba(230,190,60,.16)  border rgba(230,190,60,.28)   — money only
violet  #a8a4ff      fill rgba(143,139,255,.12) border rgba(143,139,255,.25)  — system/meta
```

**Screen glows** (one per screen, `radial-gradient`, sits under all content):
```
Today        120% 60% at 15% 0%    #12251c → #0a0b0a 55% → #080908
Active set   120% 55% at 50% 100%  #1a0d06 → #0a0908 60% → #080908
Rest         100% 50% at 50% 42%   #0d2b21 → #0a0f0d 55% → #080908
Ask          110% 45% at 50% 22%   #1a1834 → #0b0b12 52% → #080908
You          110% 40% at 50% 0%    #1c1410 → #0b0a09 55% → #080908
Hub / Diet   110% 40% at 50% 3%    #10261d → #0a0d0b 55% → #080908
Player       110% 50% at 50% 88%   #0e2a1f → #0a0c0b 55% → #080908
Expenses     110% 40% at 80% 2%    #241d0c → #0c0b09 55% → #080908
Moments      110% 38% at 50% 2%    #1b1610 → #0b0a09 55% → #080908
Settings     110% 36% at 50% 2%    #151520 → #0a0a0c 55% → #080908
```
Session card (the one saturated surface): `linear-gradient(155deg,#0f5f3f,#0a3a29 58%,#0b2a20)` + `1px rgba(31,224,138,.22)` + a green radial bloom top-right.

## 3. Type

**Manrope** — all UI text. **Azeret Mono** — every number, code, caption, timecode. **Instrument Serif italic** — the ZIVO assistant's voice, and nothing else in the app.

```
screen title       Manrope 800  27px   -.025em
hero name          Manrope 800  34px   -.03em     (exercise name)
card title         Manrope 800  30px   -.025em    (session card)
section head       Manrope 800  20px   -.02em
row title          Manrope 700  15px
body               Manrope 400  12.5–14px  / 1.5–1.65,  text-wrap: pretty
label              Manrope 600–700  11.5–13px

hero timer         Azeret 200   74px   -.06em     + centiseconds 400 26px @35%
hero metric        Azeret 300   62px   -.06em     (reps) · 300 42px -.05em (weight)
big value          Azeret 300–400  30–38px  -.04em
value              Azeret 400   18–22px  -.03em
inline value       Azeret 400   11.5–15px
caption            Azeret 500   8.5–10px  .14–.24em  UPPERCASE
assistant          Instrument Serif italic  23px (answer) / 36px (greeting)
```
Every numeric element carries `font-variant-numeric: tabular-nums`.

## 4. Geometry

```
screen padding      22px sides · 58–62px top (under status bar) · 34px bottom safe area
card radius         20–26        chip/stepper 14–18       pill 99        icon tile 10 (32px) / 18–20 (52–58px)
primary pill        60px tall (56 inside the session card)
secondary pill      52px tall            ghost: 1px rgba(255,255,255,.10) on rgba(255,255,255,.04)
stepper             52px tall, 46px −/+ zones
circular icon btn   36–40px
FAB                 58px, radius 20, bottom-right (22px, 38px)
tab bar             21px stroked icons + 8.5px mono labels, 64px slots
divider             1px hairline; inside list cards inset by the icon column (63px)
```
Icons are stroked SVG, `stroke-width` 1.7–1.9, round caps — never filled, never emoji.

## 5. Components

- **Metric card** — hairline + top-lit gradient, 20px padding, hero value block on top, 1px rule, then a 2–3-up mono footer split by vertical hairlines.
- **Progress ring** — track `rgba(255,255,255,.07)`, colored progress, round cap, rotated -90°. 74px (r32, 3px) for tiles, 104px (r46, 5px) for Diet, 290px (r132, 7px) for Rest with `drop-shadow(0 0 12px rgba(31,224,138,.45))` and a 2.4s pulsing bloom behind.
- **Session segment bar** — N equal 3px segments, 3px gap: completed green, current ember, remaining `rgba(255,255,255,.1)`; `EXERCISE 4 / 10` + `07 SETS LOGGED` beneath.
- **Spotify strip** — 3–4 bar equalizer (green, staggered 0.7–1.1s), title Manrope 700/12–13px truncating with ellipsis (never wraps), artist mono, then `elapsed · 2px hairline progress · -remaining · SPOTIFY`.
- **Music-off header chip** — `♪ CONNECT`, 36px pill, tertiary text. The only entry point when music is disconnected.
- **List row** — 32px icon tile (single-hue 13% tint + 22% border), Manrope 700/15px label, mono value, 7px chevron @30%.
- **Assistant answer** — mono `ZIVO · 0.6s` byline, Instrument Serif italic headline, a 3-up metric card with sparkline, one sentence of Manrope body, then follow-up pills. Never a wall of prose.
- **Category bar row** — label + mono amount on one line, 4px colored bar beneath. Amounts align in a single right-hand mono column.

## 6. Motion

```
press            transform: scale(.985)  (.96–.97 on FABs / circular buttons)
ghost hover      background → rgba(255,255,255,.07)
equalizer        scaleY .25 → 1, .7–1.1s ease-in-out, staggered .15s, transform-origin bottom
rest bloom       scale 1 → 1.06 / opacity .5 → .15, 2.4s ease-in-out
screen glow      opacity .55 → .9, 6s ease-in-out
timers           drive the value imperatively at 60ms; never CSS-transition a countdown ring
```
No page transitions longer than 240ms. No parallax, no spring overshoot, no confetti.

## 7. Voice

Captions are nouns (`SET VOLUME`, `UP NEXT`, `TARGET RANGE`). Buttons are verbs (`Log set`, `Skip rest`, `Set starting balance`). Deltas always state their baseline (`↑ 2.5 KG VS LAST`, `−21% VS AVERAGE`). ZIVO answers with a judgement first, then one actionable sentence — never "Here's a summary of your data."

## 8. Never

Album art or decorative imagery · emoji · gradient text · saturated multi-hue icon tiles · a second large number · ember on anything non-committing · CSS-transitioned countdowns · empty space where an optional module was · placeholder containers · light theme (dark only, for now).
