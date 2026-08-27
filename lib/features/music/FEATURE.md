# music — feature map

> A **workout-anchored** Spotify now-playing companion (not a standalone tab) + an
> immersive **Now Playing** screen with an album-artwork **color-adaptive background** and
> a subtle mini-bar tint. Restored + reshaped per [ADR-004](../../../docs/DECISIONS/ADR-004-scope-specialization.md).

## Start here

- `presentation/music_player_page.dart` — the full Now Playing screen (color-adaptive bg).
- `presentation/now_playing_bar.dart` — the compact mini-bar (album-color echo).
- `presentation/artwork_palette_service.dart` — extracts the palette from artwork bytes
  (`palette_generator`) that drives the adaptive background.
- `presentation/music_artwork.dart`, `music_scrubber.dart`, `now_playing_orb.dart` — pieces.

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

- **App Remote can't run in a simulator/emulator** — real playback needs a physical device
  with the Spotify app + Premium. `FakeMusicController` is what you develop against.
- **Android real playback is blocked on an owner dashboard task** (package name + SHA-1 +
  User Management registration), not a code bug — see [`docs/STATE.md`](../../../docs/STATE.md).
  iOS works.
- Use the **official Spotify logo asset** — trademark; don't recreate or recolor it.
