import 'package:flutter/foundation.dart';

/// A snapshot of what's currently loaded in the player — immutable, so
/// every emission on `MusicController.nowPlaying` is a full,
/// self-consistent replacement rather than a partial patch callers have to
/// merge themselves.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.trackId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.artworkBytes,
    required this.duration,
    required this.position,
    required this.isPaused,
    required this.hasControl,
  });

  final String trackId;
  final String title;
  final String artist;

  /// A URL-addressable artwork source — unused by [SpotifyMusicController]
  /// today (App Remote's `getImage` returns raw bytes, not a URL; see
  /// [artworkBytes]), but kept for any future source that IS URL-based.
  final String? artworkUrl;

  /// Raw artwork bytes — what [SpotifyMusicController] actually populates,
  /// via `SpotifySdk.getImage(imageUri: track.imageUri)`. UI (`_Artwork`/
  /// `_BigArtwork`) prefers this over [artworkUrl] when both could
  /// theoretically apply, and falls back to a placeholder icon when
  /// neither is set.
  final Uint8List? artworkBytes;

  final Duration duration;

  /// The playhead at the moment this snapshot was taken — NOT kept ticking
  /// live by the model itself. A live progress display (see
  /// `NowPlayingBar`/`MusicScrubber`) interpolates forward from this
  /// between emissions, same as any other server-timestamped progress
  /// value.
  final Duration position;

  final bool isPaused;

  /// False when another device/app is the active Spotify Connect player —
  /// playback is visible but this app can't drive it (part of Spotify's
  /// normal multi-device model, not an error state). UI should show
  /// controls as disabled/read-only rather than hide them.
  final bool hasControl;

  NowPlaying copyWith({
    String? trackId,
    String? title,
    String? artist,
    String? artworkUrl,
    Uint8List? artworkBytes,
    Duration? duration,
    Duration? position,
    bool? isPaused,
    bool? hasControl,
  }) {
    return NowPlaying(
      trackId: trackId ?? this.trackId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      artworkBytes: artworkBytes ?? this.artworkBytes,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      isPaused: isPaused ?? this.isPaused,
      hasControl: hasControl ?? this.hasControl,
    );
  }
}
