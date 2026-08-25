import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException, PlatformException, Uint8List;
import 'package:spotify_sdk/models/connection_status.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/track.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

import '../music_config.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';

/// The real binding — talks to the Spotify app via App Remote
/// (`spotify_sdk`, wrapping the native iOS/Android App Remote SDKs). Only
/// bound in production when `music_config.dart`'s `kMusicEnabled` AND
/// `spotifyClientId` are both set (see `app.dart`'s `_defaultMusic`);
/// `FakeMusicController` otherwise.
///
/// Auth note: Spotify's Authorization Code with PKCE flow needs no client
/// secret (unlike the older Authorization Code flow), so it's safe to run
/// entirely on-device — `connectToSpotifyRemote` handles the PKCE exchange
/// internally given just a `clientId` + `redirectUrl`.
///
/// App Remote requires the Spotify app installed + a Premium account, and
/// does NOT work on the iOS Simulator (real device only). The dashboard app
/// must also be in "Development mode" with the testing account added under
/// User Management, or auth fails outright.
class SpotifyMusicController implements MusicController {
  final _nowPlayingController = StreamController<NowPlaying?>.broadcast();
  final _connectionController = StreamController<MusicConnection>.broadcast();

  NowPlaying? _current;
  MusicConnection _connectionState = MusicConnection.disconnected;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<ConnectionStatus>? _connectionStatusSub;

  // getImage() is a real platform call (round-trips to the Spotify app) —
  // only refetched when the track itself actually changes, not on every
  // position/pause tick subscribePlayerState() emits.
  String? _cachedArtworkTrackUri;
  Uint8List? _cachedArtworkBytes;

  @override
  Stream<NowPlaying?> get nowPlaying => _nowPlayingController.stream;

  @override
  Stream<MusicConnection> get connection => _connectionController.stream;

  @override
  NowPlaying? get currentNowPlaying => _current;

  @override
  MusicConnection get currentConnection => _connectionState;

  void _setConnection(MusicConnection state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  @override
  Future<void> connect() async {
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    _setConnection(MusicConnection.connecting);
    try {
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: spotifyClientId,
        redirectUrl: spotifyRedirectUri,
      );
      if (!connected) {
        _setConnection(MusicConnection.disconnected);
        return;
      }
    } on PlatformException catch (e) {
      _setConnection(_mapErrorCode(e.code));
      return;
    } on MissingPluginException {
      // The native side isn't wired up on this platform (e.g. running on
      // an unsupported target) — reads the same as "can't connect" to the
      // UI, not a crash.
      _setConnection(MusicConnection.disconnected);
      return;
    }

    _setConnection(MusicConnection.connected);

    unawaited(_playerStateSub?.cancel());
    _playerStateSub = SpotifySdk.subscribePlayerState().listen(
      (state) async {
        _current = await _fromPlayerState(state);
        _nowPlayingController.add(_current);
      },
      onError: (Object error) {
        if (error is PlatformException) _setConnection(_mapErrorCode(error.code));
      },
    );

    // Catches a LATER disconnect (Spotify app closed, connection dropped) —
    // the try/catch above only covers the initial handshake.
    unawaited(_connectionStatusSub?.cancel());
    _connectionStatusSub = SpotifySdk.subscribeConnectionStatus().listen((status) {
      if (status.connected) {
        if (_connectionState != MusicConnection.connected) {
          _setConnection(MusicConnection.connected);
        }
      } else {
        _setConnection(_mapErrorCode(status.errorCode));
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _playerStateSub?.cancel();
    await _connectionStatusSub?.cancel();
    _playerStateSub = null;
    _connectionStatusSub = null;
    try {
      await SpotifySdk.disconnect();
    } on Exception {
      // Best-effort — we're tearing down our own state regardless.
    }
    _current = null;
    _nowPlayingController.add(null);
    _setConnection(MusicConnection.disconnected);
  }

  // The four controls below swallow their own errors deliberately: a stale
  // connection failing here will already have been (or will shortly be)
  // caught by the `subscribeConnectionStatus()` listener in `connect()`,
  // which is the single source of truth the UI reacts to — duplicating
  // that reaction per-control would just race it.

  @override
  Future<void> play() async {
    try {
      await SpotifySdk.resume();
    } on Exception {
      // See comment above.
    }
  }

  @override
  Future<void> pause() async {
    try {
      await SpotifySdk.pause();
    } on Exception {
      // See comment above.
    }
  }

  @override
  Future<void> next() async {
    try {
      await SpotifySdk.skipNext();
    } on Exception {
      // See comment above.
    }
  }

  @override
  Future<void> previous() async {
    try {
      await SpotifySdk.skipPrevious();
    } on Exception {
      // See comment above.
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: position.inMilliseconds);
    } on Exception {
      // See comment above.
    }
  }

  @override
  Future<void> replay() => seek(Duration.zero);

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _connectionStatusSub?.cancel();
    _nowPlayingController.close();
    _connectionController.close();
  }

  Future<NowPlaying?> _fromPlayerState(PlayerState state) async {
    final track = state.track;
    if (track == null) return null;
    return NowPlaying(
      trackId: track.uri,
      title: track.name,
      artist: track.artist.name ?? '',
      artworkBytes: await _artworkFor(track),
      duration: Duration(milliseconds: track.duration),
      position: Duration(milliseconds: state.playbackPosition),
      isPaused: state.isPaused,
      // App Remote alone can't see other Spotify Connect devices — that
      // needs the separate Web API's "available devices" endpoint, which
      // this integration doesn't call. True is a safe default until that's
      // added; a genuinely different active device would otherwise show as
      // this app having control when it doesn't.
      hasControl: true,
    );
  }

  Future<Uint8List?> _artworkFor(Track track) async {
    final uri = track.imageUri.raw;
    if (uri.isEmpty) return null;
    if (uri == _cachedArtworkTrackUri) return _cachedArtworkBytes;
    try {
      final bytes = await SpotifySdk.getImage(imageUri: track.imageUri);
      _cachedArtworkTrackUri = uri;
      _cachedArtworkBytes = bytes;
      return bytes;
    } on Exception {
      return null;
    }
  }

  /// Maps the native App Remote SDK's error codes to [MusicConnection].
  /// iOS: `CouldNotFindSpotifyApp` / `spotifyNotInstalled`. Android:
  /// `CouldNotFindSpotifyApp`, plus `AuthenticationFailedException`,
  /// `UserNotAuthorizedException`, `UnsupportedFeatureVersionException`,
  /// `OfflineModeException`, `NotLoggedInException`,
  /// `SpotifyRemoteServiceException`, `SpotifyDisconnectedException` (from
  /// `spotify_sdk`'s Android plugin source — there's no public error-code
  /// list in its docs).
  ///
  /// `UserNotAuthorizedException` used to map to [MusicConnection.needsPremium]
  /// — that was wrong. It means the app/account wasn't AUTHORIZED (in
  /// Developer Dashboard "Development mode," the usual cause is the account
  /// not being under User Management; it can also mean a declined or failed
  /// authorization), not that the account lacks Premium. The SDK has no
  /// dedicated "not Premium" code at all — see [MusicConnection.needsPremium]'s
  /// doc — so nothing here maps to it.
  MusicConnection _mapErrorCode(String? code) {
    switch (code) {
      case 'CouldNotFindSpotifyApp':
      case 'spotifyNotInstalled':
        return MusicConnection.noSpotifyApp;
      case 'UserNotAuthorizedException':
      case 'AuthenticationFailedException':
      case 'NotLoggedInException':
        return MusicConnection.authFailed;
      default:
        return MusicConnection.disconnected;
    }
  }
}
