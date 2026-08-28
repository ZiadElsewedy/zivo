# HANDOFF — Music / Now-Playing UI redesign (premium pass)

> **For the next coding agent.** This is an in-flight redesign. Read this top to
> bottom before touching the music feature — it records what shipped, the
> decisions behind it (including deliberate divergences from the design spec),
> what's verified, and the exact next steps. Keep to the existing architecture
> (`AGENTS.md`) and design language (`lib/core/theme/train_tokens.dart`,
> `assets/design_handoff_workout_tracking 2/IDENTITY.md`).

**Branch:** `version-1` · **HEAD:** `9f15302` (increments 1 & 2 were **committed
here by the owner**) · original base: `c191e33`. The owner reviews + commits
himself, so expect committed work to arrive between sessions.

**Status:** **increments 3 & 4 are uncommitted** working-tree changes (see §2b/§2c).
Increments 1 & 2 are already in `9f15302`. All four are `make gates`-clean —
`flutter analyze` clean; full suite **`+696 -46`** (the 46 pre-existing, see §7).

**Increments done so far:**
1. ✅ **Immersive Now-Playing player** — single-scroll, dynamic artwork→neon colours, Spotify branding (§3–§5). **Committed** (`9f15302`).
2. ✅ **Output/Bluetooth device row** (full controller-port seam) **+ mini-bar artwork/colour echo** (§2a, §5). **Committed** (`9f15302`).
3. ✅ **Real OS audio-route plumbing** — native iOS + Android platform channels feed `SpotifyMusicController.output` the live route (§2b). **Native compiles verified** (debug APK + iOS Runner.app both built); on-device functional test still pending (§7). **UNCOMMITTED.**
4. ✅ **Shuffle & repeat wired** — real `setShuffle`/`setRepeat` on the `MusicController` port + all 3 impls; shuffle/repeat are now **observed state** on `NowPlaying` (like `isPaused`), not local UI toggles. Spotify reads/writes them via App Remote; repeat cycles off→all→one with a repeat-one glyph (§2c, §5.3). **UNCOMMITTED — this session's delta.**

Next up: **on-device functional check of the audio route** (§6.1) — the one thing still unverified (needs hardware) — then on-device visual QA (§6.3), then roll the pass to other screens (§6.6). Shuffle/repeat wiring (was §6.2) is now done.

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

## 2. Files changed

> **Commit status:** §2 + §2a (increments 1 & 2) are **committed** in `9f15302`.
> §2b (increment 3 — the audio-route plumbing) is the **uncommitted** working-tree
> delta awaiting review. `git status` therefore shows only the §2b files.

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

### 2b. Increment 3 additions (real OS audio-route plumbing)

Replaces the increment-2 stub (`SpotifyMusicController.output` used to be
`Stream.empty()`) with a live native route. **No new Dart deps, no Xcode/Gradle
project edits** — the native code lives inline in the existing entry files.

| File | Change |
|---|---|
| `lib/features/music/data/audio_route_channel.dart` | **New.** `AudioRouteChannel` — a `MethodChannel('zivo/audio_route')` (`current`) + `EventChannel('zivo/audio_route/events')` (live changes). Maps the native map `{name, kind, battery?}` → `AudioOutput`. Swallows `MissingPluginException`/stream errors → `null` (so the sim/desktop/tests are safe). |
| `lib/features/music/data/spotify_music_controller.dart` | Added a constructor that calls `_watchAudioRoute()` — seeds `current()` then subscribes to `changes()`, pushing onto the existing `_outputController`; `output`/`currentOutput` now come from the route; `dispose` cancels the sub + closes the controller. |
| `ios/Runner/AppDelegate.swift` | Added an inline `AudioRoute: NSObject, FlutterStreamHandler`. Reads `AVAudioSession.sharedInstance().currentRoute.outputs.first`; maps `portType`→kind; observes `routeChangeNotification`. Registered from `didInitializeImplicitFlutterEngine` via the implicit-engine registrar (held on a strong `audioRoute` property). Battery omitted (no public iOS API). |
| `android/.../MainActivity.kt` | Added `configureFlutterEngine`/`cleanUpFlutterEngine` + an inline `AudioRoute: EventChannel.StreamHandler`. Reads `AudioManager.getDevices(GET_DEVICES_OUTPUTS)`, picks the active output by preference (BT > wired/USB > builtin speaker), maps `AudioDeviceInfo.type`→kind, registers an `AudioDeviceCallback` for live changes. Battery omitted (no stable public API). |

The channel contract (native → Dart) is a map or null:
`{ "name": String, "kind": "bluetooth"|"headphones"|"speaker"|"phone", "battery": int? }`.

### 2c. Increment 4 additions (shuffle & repeat wired — this session)

Turns the old visual-only shuffle/repeat toggles into real **observed** playback
state — the same fire-and-observe contract as play/pause: the UI never holds a
local toggle, it renders `NowPlaying.isShuffling` / `.repeatMode`, and the new
value flows back on `nowPlaying`. No new deps.

| File | Change |
|---|---|
| `lib/features/music/domain/now_playing.dart` | New `enum MusicRepeatMode { off, all, one }` + two `NowPlaying` fields: `isShuffling` (bool) and `repeatMode` (default `off`), threaded through `copyWith`. **Named `MusicRepeatMode`, not `RepeatMode`** — both Flutter Material *and* `spotify_sdk` already export a `RepeatMode`; a distinct name keeps every consumer unambiguous (this bit once, mid-session — leave it renamed). |
| `lib/features/music/domain/music_controller.dart` | Port gains `Future<void> setShuffle(bool)` + `Future<void> setRepeat(MusicRepeatMode)`. Explicit-target (`setRepeat(mode)`), **not** `cycleRepeat()` — matches `seek`'s style; the UI owns the off→all→one→off cycle order. |
| `lib/features/music/data/spotify_music_controller.dart` | Reads `state.playbackOptions.isShuffling` / `.repeatMode` off the App Remote player state into `NowPlaying` (so it reflects a change made on any device); `setShuffle`→`SpotifySdk.setShuffle`, `setRepeat`→`SpotifySdk.setRepeatMode`. Import trick: `import '…/spotify_sdk.dart' hide RepeatMode;` + `import '…/enums/repeat_mode_enum.dart' as sdk;` (the package ships *two* same-named `RepeatMode` types); the state is read by `.name` to dodge the other one. `all`↔Spotify `context`, `one`↔`track`. |
| `lib/features/music/data/fake_music_controller.dart` | Holds `_shuffle`/`_repeatMode`, emits them; `setShuffle`/`setRepeat` update + emit. Playback now honours them: repeat-one restarts the track at natural end (explicit next/prev still skip), shuffle picks a random *other* track. |
| `test/support/inert_music_controller.dart` | `setShuffle`/`setRepeat` no-ops (keeps the ~30 `wrapWithScope` sites compiling). |
| `lib/core/theme/app_icons.dart` | Added `repeatOne` (`LucideIcons.repeat1`) for the repeat-one state. |
| `lib/features/music/presentation/music_player_page.dart` | `_ImmersivePlayer` is now **stateless** (the local `_shuffle`/`_repeat` are gone). `_Controls` renders shuffle/repeat from `playing`, computes the repeat cycle, swaps in the repeat-one glyph, and — new — **disables** shuffle/repeat when `!hasControl` (still showing their state), consistent with prev/next. |
| `test/music/music_player_page_test.dart` | +2 tests: shuffle drives the controller & reflects state; repeat cycles off→all→one→off with the glyph swap. (Tall viewport so the controls are on-screen to tap; still never `pumpAndSettle`.) |

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
3. **Shuffle & repeat are now fully wired (increment 4).** Real `setShuffle` /
   `setRepeat` on the port, driving Spotify for real; the controls render the
   **observed** `NowPlaying.isShuffling` / `.repeatMode` (not a local toggle), so
   they reflect Spotify's truth — including a change made on another device.
   Repeat is tri-state (off→all→one) with a repeat-one glyph. See §2c. (The old
   `_ImmersivePlayerState` visual-only toggle is gone — that widget is stateless now.)
4. **The player now uses `TrainColors`/`TrainType`** (the cool `#080908` handoff
   system), not the old warm `AppColors`. This unifies it with the strips and the
   rest of the workout-tracking surfaces.

---

## 6. What remains — exact next steps (in priority order)

**✅ Done (increment 2):** output/Bluetooth device row (full port seam, `_OutputRow`
in the player, fixture device in dev) and the mini-bar artwork/colour echo. See §2a.
**✅ Done (increment 3):** real OS audio-route plumbing (native iOS + Android). See §2b.
**✅ Done (increment 4):** shuffle/repeat wired — port verbs + observed `NowPlaying` state + tri-state repeat. See §2c.

1. **On-device functional check of the audio route** — the code compiles on both
   platforms (§7) but has NOT been run on hardware. On a real iPhone/Android with
   Spotify Premium: connect BT headphones → confirm the player's output row shows
   the device name + `bluetooth` glyph, unplug/plug wired → confirm it flips live.
   Watch for these known caveats, and adjust only if they misbehave:
   - **iOS** reads *this app's* `AVAudioSession.currentRoute`. That reflects the
     system hardware output in the common case, but the app never activates an
     audio session (Spotify plays in its own process) — if the route reads
     stale/empty, set a category once at launch
     (`try? AVAudioSession.sharedInstance().setCategory(.playback)`).
   - **Android** has no public "active output" API pre-31, so `pickActive`
     guesses by preference (BT > wired/USB > builtin speaker). If the guess is
     wrong on some device, prefer `AudioManager.getDevices` filtered by what's
     actually routing, or gate on API 31+ `AudioManager.getAudioDevicesForAttributes`.
   - **Battery %** is intentionally omitted on both (no stable public API). The
     UI already hides the battery pill when null, so the row reads "AirPods Pro"
     with no percent — that's expected, not a bug.
   - Optionally **hide the builtin `phone` kind** (only show external devices) —
     one-line filter in the player's `StreamBuilder<AudioOutput?>` if desired.
2. ✅ **Shuffle / repeat — DONE (increment 4).** `setShuffle(bool)` /
   `setRepeat(MusicRepeatMode)` on the port + all 3 impls; observed state on
   `NowPlaying`; tri-state repeat with a repeat-one glyph (§2c). The one thing the
   sim can't confirm: that Spotify actually **applies** them on a real device —
   verify alongside §6.1/§6.3 (toggle shuffle & cycle repeat on hardware, watch
   the queue behave and the controls stay in sync if you also change them in the
   Spotify app).
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

- `flutter analyze` — **clean** (whole project, after all four increments).
- `flutter test test/music/music_player_page_test.dart` — **green** (3 tests:
  render/branding/output row `Fixture Buds`/`72%`/bluetooth; shuffle drives the
  controller & reflects state; repeat cycles off→all→one→off with the glyph swap).
- **Native compiles verified** (the route plumbing): `flutter build apk --debug`
  → `✓ Built app-debug.apk` (Kotlin OK) and `flutter build ios --debug
  --no-codesign` → `✓ Built Runner.app` (Swift OK). **Not** yet run on hardware —
  the live BT-device behaviour is the outstanding functional check (§6.1).
- **Full suite: `+696 -46`** (693 pre-existing passes + the 3 music tests; the
  interface change, mini-bar echo, route plumbing, and shuffle/repeat added
  **zero** Dart regressions — `SpotifyMusicController`/the channel aren't
  instantiated in tests). The 46 failures are **pre-existing on `version-1` and
  NOT caused by this work** — proven in increment 1 by stashing the music files
  back to `HEAD`: the baseline was byte-identical `+693 -46`. None of the failing
  tests reference music/player/spotify/scrubber/artwork. They span auth/home/
  workout/ai/diet/expenses/moments and look like fallout from the in-flight
  Today/live-session redesign — a **separate** cleanup, out of scope here.
  ```bash
  flutter test 2>&1 | tail -1   # expect +696 -46 until those are fixed elsewhere
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
