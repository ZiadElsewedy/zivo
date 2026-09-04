# music — feature map

> A **workout-anchored** Spotify now-playing companion (not a standalone tab) + an
> immersive **Now Playing** screen with an album-artwork **color-adaptive background** and
> a subtle tint on the strip fused to the nav island. Restored + reshaped per [ADR-004](../../../docs/DECISIONS/ADR-004-scope-specialization.md).

## Start here

- `presentation/music_player_page.dart` — the full Now Playing screen (color-adaptive bg).
- `presentation/now_playing_lozenge.dart` — the slim strip **fused to the top edge of
  the shell's nav island** (album-color echo), and the app's one permanent music
  surface. It renders **every connection state**, not just a live track: connecting,
  dropped (→ *Reconnect Spotify*, and the strip IS the button), no Spotify app, nothing
  loaded. With a track it carries the full transport — previous · play/pause · next —
  plus a hairline playhead along its bottom edge. Owns `kNowPlayingLozengeHeight`, which
  `ZivoBottomBarMetrics` imports — see the shell's `bottom_chrome.dart`.
- `presentation/artwork_palette_service.dart` — extracts the palette from artwork bytes
  (`palette_generator`) that drives the adaptive background.
- `presentation/spotify_strip.dart` — the three-density now-playing strip used across the
  workout screens (`full` on Today, `inline` while logging, `rest` between sets). Carries
  the **album-art tile + Spotify mark**, and takes an `accent` its host supplies so its
  transport controls follow the current track's colour.
- `presentation/music_artwork.dart`, `music_scrubber.dart` — pieces.

## Staying connected (the default, not a user chore)

Connecting **links the device**: `MusicController.connect()` records per-device consent
(`data/spotify_link_store.dart`, SharedPreferences — consent, never a credential) and
from then on `isLinked` is true. A linked device reattaches on its own —

- at launch (`SpotifyMusicController`'s constructor restores the link and connects),
- on **every app resume** (`ZivoApp` is a `WidgetsBindingObserver` and calls
  `reconnectIfLinked()`; App Remote routinely dies while ZIVO is backgrounded, so this
  is the one that matters most in practice), and
- after a drop, on a bounded backoff (2s → 5s → 12s → 30s, then wait for the next
  resume).

Two states are deliberately **terminal**: `authFailed` (retrying can throw an
authorization sheet at the user) and `noSpotifyApp` (retrying cannot succeed). Both
surface a tappable affordance instead. `disconnect()` means **unlink** — it clears the
consent so nothing reconnects behind the user's back; the only place that offers it is
Settings' Music card.

`linked` is not `connection`: a linked device is routinely disconnected, and that
distinction is what keeps the strip on screen with a reconnect on it (below) instead of
vanishing.

## Controller seam (`AppScope.music`, nullable)

- **`MusicController`** (`domain/music_controller.dart`) with two impls in `data/`:
  - `fake_music_controller.dart` — **the default / what the app runs on** offline and in
    tests (and when `kMusicEnabled` is off).
  - `spotify_music_controller.dart` — real Spotify **App Remote** via `spotify_sdk`.
- Selected in [`app.dart`](../../app/app.dart) `_defaultMusic()`:
  `SpotifyMusicController` only when `kMusicEnabled && spotifyClientId.isNotEmpty`,
  else `FakeMusicController`.
- Config + feature flag: `music_config.dart` (`kMusicEnabled`, `spotifyClientId`, the
  `zivo://spotify-callback` redirect). Domain: `now_playing.dart`, `music_connection.dart`.

## Gotchas

- **The strip's states must all fit one height.** Every branch of the lozenge renders at
  exactly `kNowPlayingLozengeHeight`, because the shell reserved that on every page
  before knowing which branch it would be. Covered by
  `test/music/now_playing_lozenge_test.dart`.
- **Don't put a Connect prompt on a device that has never linked.** The strip mounts for
  a linked device or a live track and nothing else; the shell's `_resolveVisible()` is
  the same predicate. A user who doesn't use Spotify gets no bar and no reserved height.

- **The strip is part of the bottom chrome, not a layer above it.** It renders inside
  `ZivoBottomBar`'s clip via that widget's `fused` slot, and its height is reserved on
  every page through `BottomChrome`. Changing `kNowPlayingLozengeHeight` changes every
  surface's bottom padding — that coupling is deliberate. There is no longer a
  swipe-to-collapse orb: it existed only to shrink a too-tall bar, and it collided with
  the Ask composer and with list rows.
- **App Remote can't run in a simulator/emulator** — real playback needs a physical device
  with the Spotify app + Premium. `FakeMusicController` is what you develop against.
- **Android real playback is blocked on an owner dashboard task** (package name + SHA-1 +
  User Management registration), not a code bug — see [`docs/STATE.md`](../../../docs/STATE.md).
  iOS works.
- Use the **official Spotify logo asset** — trademark; don't recreate or recolor it. It
  appears where a track is genuinely playing *from* Spotify (the strip's artwork tile, the
  player's source badge) — not on empty/disconnected slots, which would claim a connection
  that isn't there.
- **The "no artwork tile" rule is retired** (owner call). The original handoff had the
  strips text-first with an [EqualizerGlyph] instead of a cover, so nothing competed with
  each screen's hero number; recognising the track mid-set turned out to matter more. The
  equalizer survives as an overlay on the tile and as the no-bytes fallback — don't
  "restore" the text-only strip on the strength of the old comments.
