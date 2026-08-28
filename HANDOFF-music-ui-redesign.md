# HANDOFF — Music / Now-Playing UI redesign (premium pass)

> **For the next coding agent.** This is an in-flight redesign. Read this top to
> bottom before touching the music feature — it records what shipped, the
> decisions behind it (including deliberate divergences from the design spec),
> what's verified, and the exact next steps. Keep to the existing architecture
> (`AGENTS.md`) and design language (`lib/core/theme/train_tokens.dart`,
> `assets/design_handoff_workout_tracking 2/IDENTITY.md`).

**Branch:** `version-1` · **Base commit when this work started:** `c191e33` ·
**Status:** _uncommitted working-tree changes_ (owner Ziad commits himself).

**Increments done so far (all uncommitted, all `make gates`-clean):**
1. ✅ **Immersive Now-Playing player** — single-scroll, dynamic artwork→neon colours, Spotify branding (§3–§5).
2. ✅ **Output/Bluetooth device row** (full controller-port seam) **+ mini-bar artwork/colour echo** (§2a, §5).

Next up: wire shuffle/repeat, real native output plumbing, on-device QA, then roll the pass to other screens (§6).

---

## 1. Context / the brief

Ziad is doing an app-wide premium UI pass. This first, agreed increment is the
**flagship music / Now-Playing experience**. The three forks were locked with him
up front:

| Decision | Choice |
|---|---|
| Artwork vs the spec's "no album art" | **Immersive artwork glow** — cover is the hero; the screen's neon glow + scrub line are pulled from the artwork and animate on track change. A deliberate, owner-signed divergence from `IDENTITY.md`. |
| Where to start | **Music / Now-Playing first**, then roll the spacing/premium pass out screen-by-screen. |
| Who implements | **Claude writes the Flutter directly**; Ziad reviews + commits. |

Other explicit asks from the brief, and how they're handled here:
- **Keep Spotify integration** → kept + branded (real logo asset + wordmark + live equalizer).
- **Keep the neon/glow system, colours dynamic to the song** → done on the player (see §3).
- **Single animated scroll, connected — not disconnected sections** → the player is one `SingleChildScrollView` with staggered `RiseIn` entrance (see §4 for why not `spaceBetween`).
- **Show connected Bluetooth/output device + "playing from Spotify"** → Spotify branding done; **output-device row now built** (full controller-port seam; fixture device in dev, real route needs a native channel — see §2a/§6). Not faked.

---

## 2. Files changed (all under the working tree, uncommitted)

| File | Change |
|---|---|
| `lib/features/music/presentation/music_player_page.dart` | **Full rewrite.** The immersive, single-scroll Now-Playing screen. |
| `lib/features/music/presentation/artwork_palette_service.dart` | Extended: now yields an **`ArtworkColors { background, accent }`** pair (was a single background `Color`). Adds the neon-accent extraction; `ArtworkPalette` widget tweens both. |
| `lib/features/music/presentation/music_scrubber.dart` | Added an `accentColor` param (defaults to ember) so the scrub line/thumb take the track's neon; timecodes switched to mono (`TrainType`). Used **only** by the player. |
| `lib/core/theme/app_icons.dart` | Added `chevronDown`, `shuffle`, `repeat`, `headphones`, `bluetooth`, `speaker` (purely additive). |
| `test/music/music_player_page_test.dart` | **New** — first test for the music player (renders/branding/no-overflow/no-artwork fallback/output row). |

### 2a. Increment 2 additions (output device row + mini-bar echo)

| File | Change |
|---|---|
| `lib/features/music/domain/audio_output.dart` | **New.** `AudioOutput { name, kind, batteryPercent? }` value type + `AudioOutputKind` enum. Pure domain, no colour/widgets. |
| `lib/features/music/domain/music_controller.dart` | Added `Stream<AudioOutput?> get output` + `AudioOutput? get currentOutput` to the port. |
| `lib/features/music/data/fake_music_controller.dart` | Emits a fixture Bluetooth device (`Fixture Buds`, 72%) so the row is demoable in-sim; null when disconnected; closes the new controller in `dispose`. |
| `lib/features/music/data/spotify_music_controller.dart` | `output` = `const Stream.empty()`, `currentOutput` = `null` (App Remote can't report the OS route — TODO comment points at the native channel). |
| `test/support/inert_music_controller.dart` | `output` empty stream, `currentOutput` null (keeps ~30 `wrapWithScope` test sites compiling). |
| `lib/features/music/presentation/music_player_page.dart` | Added `_OutputRow` widget + a `StreamBuilder<AudioOutput?>` that renders it **only when a device is known**. |
| `lib/features/music/presentation/now_playing_bar.dart` | Mini-bar now wraps its frosted plate in `ArtworkPalette` for a **subtle artwork colour echo** (faint accent wash + soft accent glow). Confined to the mini-bar; the in-set strips are untouched. |

**Deliberately NOT touched:** the `NowPlaying` model, `spotify_strip.dart`,
`equalizer_glyph.dart`, `music_artwork.dart`, and the collapsed `MusicOrb`
(`now_playing_orb.dart`) — the orb could get the same echo later if wanted.

---

## 3. How the dynamic colour system works (the marquee feature)

`ArtworkPaletteService.coloursFor(trackId, bytes)` runs `palette_generator` off
the main thread and returns `ArtworkColors`:
- **`background`** — a dark, WCAG-AA-readable wash (existing logic, kept).
- **`accent`** — NEW. The cover's most vivid swatch pushed into a bright,
  saturated *neon* (HSL: saturation floored ~0.6, lightness clamped 0.55–0.72).
  It's a glow colour, never text, so it's deliberately not contrast-limited.
- Fallback when there's no cover / extraction fails: `ArtworkColors.fallback`
  (`TrainColors.base` ground + `TrainColors.green` neon). Results are cached
  per-track (process-lifetime static map); a `_disposed` guard drops stale work.

`ArtworkPalette` (StatefulWidget) resolves + **tweens both colours** (two nested
`TweenAnimationBuilder`s, 700ms easeOut) so the whole screen glides to the new
song's palette. It's confined to the music UI (only the player builds one).

On the player these colours drive: the `Scaffold` background, the breathing
`_AmbientGlow` (a 6s radial bloom in `accent`), the artwork's neon halo shadow,
the `MusicScrubber` accent, and the equalizer glyph.

> ⚠️ **You can't see this in the simulator.** `FakeMusicController` (the default
> dev runtime) ships artwork-less fixture tracks, so the player falls back to the
> neutral ground + green neon. The dynamic colour only lights up with **real
> Spotify artwork bytes**, which needs a physical iOS device + Spotify Premium
> (App Remote can't run in a sim — see `music/FEATURE.md`). The logic is unit-safe
> and the fallback is intentional.

---

## 4. Player structure & the layout gotcha (READ before editing the player)

The player is `SingleChildScrollView` → `Column` (top-aligned) with three
`RiseIn` groups: **[top bar] · [Spotify brand + artwork hero + title/artist] ·
[scrubber + transport]**, generous tuned gaps between them.

**Do NOT wrap it in a fill-to-viewport widget** (`IntrinsicHeight`,
`SliverFillRemaining(hasScrollBody:false)`, or `Column(mainAxisAlignment:
spaceBetween)` inside a min-height box). All of those **query child intrinsic
dimensions**, and `MusicScrubber` contains a `LayoutBuilder`, which throws
`"LayoutBuilder does not support returning intrinsic dimensions"` and cascades
into null-check crashes. I hit this twice — the current top-aligned scroll is the
robust resolution. If you want bottom-anchored controls on tall screens, the safe
path is to remove the `LayoutBuilder` from `MusicScrubber` first (measure track
width another way), not to re-add an intrinsic-querying wrapper.

**Animation caveats for tests:** the ambient glow (`_AmbientGlow`) and the
`EqualizerGlyph` repeat forever → **never `pumpAndSettle`** a mounted player
(it hangs); pump a bounded duration. `FakeMusicController` owns a real periodic
ticker → dispose it **inside the test body** (`finally`), not via `addTearDown`
(the pending-timer invariant runs first). Both are demonstrated in the new test.

---

## 5. Deliberate decisions & divergences (don't "fix" these blindly)

1. **Album art on the player** contradicts `IDENTITY.md` §1.4 / §8 ("no album
   art"). This is intentional and owner-approved, and scoped to the player ONLY.
   Everywhere else the text-first rule still holds.
2. **Mini-bar artwork echo — added in increment 2, scoped tightly.** The mini
   bar (`NowPlayingBar`) now carries a *subtle* echo of the cover colour (a
   faint accent wash on the frosted plate + a soft accent glow), owner-requested.
   It stays **text-first** (no artwork *tile*; the equalizer glyph still carries
   "it's playing") and is kept very low-alpha so it never competes with a
   screen's hero number. Crucially it is applied at the `NowPlayingBar` level,
   **not** inside `SpotifyStrip` — so the in-set `inline`/`rest` strip variants
   (Active-Set/Rest), which a prior pass deliberately stripped of tint, remain
   untouched. Don't push this echo into `SpotifyStrip` itself.
3. **Shuffle & repeat are visual-only toggles.** The `MusicController` port has no
   `setShuffle`/`setRepeat`, so they toggle their own highlight but don't change
   Spotify's queue. Clearly a "90% of the design, honest about the 10%" call —
   see the `// visual-only` note in `_ImmersivePlayerState`. Wire them in §6.
4. **The player now uses `TrainColors`/`TrainType`** (the cool `#080908` handoff
   system), not the old warm `AppColors`. This unifies it with the strips and the
   rest of the workout-tracking surfaces.

---

## 6. What remains — exact next steps (in priority order)

**✅ Done (increment 2):** output/Bluetooth device row (full port seam, `_OutputRow`
in the player, fixture device in dev) and the mini-bar artwork/colour echo. See §2a.

1. **Populate the REAL output route** (the seam is in place; only the data is
   stubbed). `SpotifyMusicController.output` currently emits nothing — App Remote
   doesn't expose the OS audio route. Add a platform channel:
   - iOS: `AVAudioSession.sharedInstance().currentRoute.outputs` → map
     `portType` (`.bluetoothA2DP`/`.headphones`/`.builtInSpeaker`…) to
     `AudioOutputKind`; battery for BT devices isn't generally available.
   - Android: `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` / `MediaRouter`.
   - Push `AudioOutput`s onto a broadcast controller in `SpotifyMusicController`.
     Device-only to verify; the UI + fake already exercise the render path.
2. **Wire shuffle / repeat** — add `setShuffle(bool)` / `cycleRepeat()` to the
   port + all 3 impls (`spotify_sdk` support is limited; confirm what 3.0.2
   exposes — `SpotifySdk.setShuffle`/`setRepeatMode` exist), then replace the
   local `_shuffle`/`_repeat` state in `_ImmersivePlayerState`. Today they're
   visual-only toggles (§5.3).
3. **On-device visual QA** — run on a real iPhone with Spotify Premium to see the
   dynamic colour + real artwork + real output device, and sanity-check
   spacing/entrance on small (SE) and large (Pro Max) screens. The one thing the
   sim/tests can't cover.
4. **Swipe-down-to-dismiss** the fullscreen player (matches the mini-bar's
   swipe language) — optional polish; today it's the chevron + the platform route.
5. **(Optional) echo on the collapsed `MusicOrb`** (`now_playing_orb.dart`) for
   consistency with the mini-bar — same `ArtworkPalette` wrap, very low alpha.
6. **Roll the premium pass onward** (per the agreed sequence): Today → You →
   Diet → Expenses → Moments → Settings, reusing `train_chrome.dart` primitives
   and the spacing rhythm. See `assets/design_handoff_workout_tracking 2/` for
   each screen's intent.

---

## 7. Verification (current state)

- `flutter analyze` — **clean** (whole project, after both increments).
- `flutter test test/music/music_player_page_test.dart` — **green** (1 test;
  now also asserts the output row: `Fixture Buds` / `72%` / bluetooth icon).
- **Full suite: `+694 -46`** (693 pre-existing passes + this test; the interface
  change + mini-bar echo added **zero** regressions). The 46 failures are
  **pre-existing on `version-1` and NOT caused by this work** — proven in
  increment 1 by stashing the music files back to `HEAD`: the baseline was
  byte-identical `+693 -46`. None of the failing tests reference
  music/player/spotify/scrubber/artwork. They span auth/home/workout/ai/diet/
  expenses/moments and look like fallout from the in-flight Today/live-session
  redesign — a **separate** cleanup, out of scope here.
  ```bash
  flutter test 2>&1 | tail -1   # expect +694 -46 until those are fixed elsewhere
  ```
- **`docs/STATE.md` NOT updated** (left to whoever commits, per shared-tree
  caution). On commit, add an update-log line and note the music player redesign.

## 8. How to see it

- Fastest correct check: `flutter test test/music/music_player_page_test.dart`.
- In-app (sim): sign in → the mini "now playing" bar mounts (FakeMusicController
  auto-connects + plays; note its subtle glow echo) → tap it to push
  `MusicPlayerPage`. You'll see the full layout/branding/controls **and the output
  row** (the fixture `Fixture Buds · 72%`), but the **neutral fallback glow
  colours** (no fixture artwork). For the real dynamic colour + real output
  device, use a physical iPhone + Spotify Premium.
