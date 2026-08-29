# Prompt for Claude Code — ZIVO gym app (11 screens)

Paste this file into Claude Code. `IDENTITY.md` (same folder) is the binding visual spec; `Workout Tracking.dc.html` is the working prototype — open it in a browser to see every screen live.

---

You are implementing the ZIVO mobile app. A high-fidelity prototype of eleven screens is provided in this folder, plus `IDENTITY.md`, which is the complete design language: colors, type scale, geometry, components, motion, voice.

**Read `IDENTITY.md` first and treat it as binding.** The HTML is a visual reference, not code to copy — recreate it in this codebase's existing environment (React Native / Expo / SwiftUI / whatever is already here), using established components, navigation, and state patterns. If no environment exists yet, choose one and say why before starting.

Fidelity: **high**. Every value in `IDENTITY.md` is final. Where the prototype and the identity doc disagree, the identity doc wins.

## Build order

1. **Tokens + primitives** — colors, the two type ramps (Manrope UI / Azeret Mono numeric), spacing, radii. Then: MetricCard, ProgressRing, SegmentBar, Stepper, PrimaryPill, GhostPill, ListRow, IconTile, SpotifyStrip, CaptionLabel, Fab. Every numeric text style must set tabular numerals at the primitive level so no screen has to remember.
2. **Workout flow** — Hub → Active set → Rest. This is the product; get it exact first.
3. **Today, Ask, You.**
4. **Diet, Expenses, Moments, Settings, Player.**

## Screens

### Today (home)
Mono date caption · clock (Azeret 300/54px) with meridiem baseline-aligned · `Evening, Ziad` (Manrope 800/27px) · two 40px circular glass buttons top-right (mic, DND — DND tints violet when active). Then a 3-up ring tile card (Trained / Steps / Volume — green complete, white 69%, ember 81%) with Manrope label + mono sub each. Then the session card: green `PULL` dot-tag, `Change` outlined pill, `Pull Day 1`, 3-stat mono row (10 exercises · 24 sets · ~65 min), 56px ember `Start Workout`. Spotify strip, then tab bar (TODAY / HUB / ASK / YOU).

### Active set
Header: 36px close · centered `DAY 2 · PULL DAY 1` + session elapsed · 36px delete (or the `♪ CONNECT` chip when music is off). SegmentBar 10 · `EXERCISE 4 / 10` + `07 SETS LOGGED`. `NOW` ember caption, `Lat Pull Down` (Manrope 800/34px), `LATS · BICEPS · WIDE GRIP`. Two set chips (SET 1 ember-active, SET 2 inert). Hero card: `GOAL` + reps 62px, weight 42px + `KG` + delta caption (green up / ember down / dim matching), rule, then LAST TIME · TARGET RANGE · RPE. Two steppers (reps ±1 clamp 1–30, weight ±2.5 clamp ≥0) driving the hero live. Footer: 112px `Skip` ghost + ember `Log set`.
**Music off variant:** the strip's ~74px becomes the set ledger — one mono row per logged set (SET 1 `10 × 40`, SET 2 `9 × 40`, current set ember) with volume bars, plus `1.08t VOLUME` for the exercise. Nothing above the footer moves.

### Rest
Same header + SegmentBar (4 green) with `SET LOGGED · 8 × 45` in green. Centered `REST` pill. 290px ring (see identity §5) with `1:29` + `.46` and `OF 2:00 PLANNED`. `UP NEXT` card: `Seated Row · Wide Grip` / `10 × 40` + `SET 1 · KG`. Spotify strip. `−15s` / `+15s` ghosts, then green `Skip rest` with dark `#04140d` label.
**Music off variant:** two tiles instead of the strip — HEART RATE (`118 BPM`, `↓ 26`, falling sparkline) and SET VOLUME (`360 KG`, `1.08t THIS EXERCISE`).

### Ask (ZIVO)
Empty state: violet 54px glyph tile, `Hey, I'm ZIVO.` in Instrument Serif italic 36px, one line of body, four suggestion pills. Answered state: user question as a right-aligned bubble, `ZIVO · 0.6s` byline, Instrument Serif italic headline, a 3-up mono metric card with a green area sparkline, one sentence of body, follow-up pills. 58px input pill with mic + send. Four canned answers exist in the prototype (training / spend / diet / week) — wire to the real assistant.

### You
96px avatar in an ember progress ring with a camera badge · `Ziad` · verified email line · 3-up stat card (128 sessions / 14 months / 412t lifetime) · dashed `About` empty state · ACCOUNT list (Name, Date of birth) · SIGN-IN row (Google, green CONNECTED) · Spotify strip · tab bar.

### Workout hub
Back + `Workout` + green stats button · session card (`DAY A · PUSH`, 7/14/~21, ember Start) · 2×2 stat tiles, each with a sparkline or bar cluster instead of a chevron (Sessions 3/4, Streak 6 days, Duration 52 min avg, Usual start 19:40) · BODYWEIGHT card: `78.6 KG` + `Log weigh-in` ghost + green area chart with an end dot, `JUL 1` → `TODAY`.

### Player
Chevron-down · `PLAYING FROM / Pull Day · Heavy` · overflow. Type-led hero: equalizer + `SPOTIFY · TRACK 07`, title Manrope 800/40px, artist mono 15px, `ALBUM · SINGLE · 2024`. 40-bar waveform, dim, clipped to the played fraction in green; `0:06` / `-2:44` beneath. Controls: shuffle · prev · 76px ember play/pause · next · repeat. Output row: AirPods Pro, `72%`, chevron. **No artwork tile** — see identity §1.4.
Track title truncates with ellipsis on one line everywhere; never wraps.

### Diet
Back · `Diet` · basket. `BALANCED · TARGET 2200 KCAL`. Hero card: 104px green ring with kcal-left inside, `n of 3 meals eaten`, `x EATEN · PLAN 1270`, then three macro bars (protein green /114g, carbs violet /116g, fat amber /33g). MEALS: three tappable rows (24px check that fills green when eaten) with mono items caption and right-aligned `310` + `KCAL · P 8G`. Ticking a meal updates the ring and all three bars live. FULL PLAN card (`Every day` / `1270 kcal`, three label-value lines). Ember FAB.

### Expenses
Back · `Expenses` · filter. Amber wallet-setup card: `SET UP YOUR WALLET`, `How much do you have right now?`, one line of body, solid amber `Set starting balance` with dark label. `THIS WEEK` + `685 EGP` right-aligned, then four category rows (label + mono amount, 4px bar: Food ember 63%, Groceries green 18%, Transport violet 13%, Coffee amber 7%). Then TODAY / YESTERDAY groups, each a hairline card of rows with a 4px colored spine, title, `08:40 · CARD` mono caption, and the amount in one right-hand mono column. Amber FAB. **No per-row saturated icon tiles.**

### Moments
Back · `Moments` · upload. Filter pills (All ember / Photos / Notes / PRs). `YESTERDAY · 1 ENTRY` then the note card: `NOTE · 1D AGO` caption, 16px body, rule, `PULL DAY 1 · WEEK 3` + green `OPEN`. Below, a centered empty state (dashed 52px camera tile, `Nothing else logged yet`, one line of body). Ember camera FAB.

### Settings
Back · `Settings`. MEDIA: Storage & sync `1.2 GB`. MUSIC: Spotify card with a live equalizer tile, `CONNECTED · PLAYING`, and a second line carrying the actual track + `-2:37` (the row's claim must be informative). APP list: Theme (violet, `Dark`), Version `1.0.0 (1)`, Build `Development`, Privacy policy. ACCOUNT: Delete account (ember tile, `PERMANENT · 128 SESSIONS`). Ghost `Sign out` pinned to the bottom.

## Behavior

- **Rest timer** counts at 60ms and renders centiseconds; drive the digits and the ring's `stroke-dashoffset` imperatively from a wall-clock timestamp diff — never re-render the tree at 60ms and never CSS-transition the ring. Timers must survive backgrounding. ±15s clamps at 0 and raises `total` so the ring stays ≤100%. Announce 10s and 3s with haptics.
- **Set flow:** log set → chip fills, counter increments, navigate to Rest with the logged numbers echoed in the header; on rest end or skip → next set/exercise.
- **Spotify:** position advances while playing, auto-advances at track end; next/prev reset to 0; pause freezes the equalizer. Wire the real Spotify SDK; the prototype uses a local track list. Music is **optional** — when disconnected, render the music-off layouts and the `♪ CONNECT` header chip.
- **Diet:** meal toggles recompute kcal left, ring offset, and macro bars.
- **Accessibility:** every tap target ≥44px (stepper zones are 46×52). Dynamic Type: hero numerals may scale up to 1.3× before the layout reflows; captions never shrink below 8.5px.

## State

`restRemainingMs`, `restTotalMs`, `reps`, `weight`, `currentSetIndex`, `loggedSets[]`, `exerciseIndex`, `sessionStartedAt`, `spotify {connected, trackId, positionMs, playing}`, `meals[]`, `assistantThread[]`, `wallet {balance, entries[]}`.

## Out of scope

Onboarding, plan editing, light theme, social/sharing, the wallet-setup sheet itself.
