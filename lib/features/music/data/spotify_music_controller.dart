import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException, PlatformException, Uint8List;
import 'package:spotify_sdk/enums/repeat_mode_enum.dart' as sdk;
import 'package:spotify_sdk/models/connection_status.dart';
import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/track.dart';
// `hide RepeatMode`: `spotify_sdk` re-exports its own `RepeatMode`, which would
// otherwise clash with this app's domain `RepeatMode` (from now_playing.dart).
// The SDK enum is still needed for `setRepeatMode`, imported prefixed as `sdk`.
import 'package:spotify_sdk/spotify_sdk.dart' hide RepeatMode;

import '../music_config.dart';
import '../domain/audio_output.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'audio_route_channel.dart';
import 'spotify_link_store.dart';

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
  SpotifyMusicController({SpotifyLinkStore? links})
    : _links = links ?? SpotifyLinkStore() {
    _watchAudioRoute();
    unawaited(_restoreLink());
  }

  final SpotifyLinkStore _links;

  final _nowPlayingController = StreamController<NowPlaying?>.broadcast();
  final _connectionController = StreamController<MusicConnection>.broadcast();
  final _outputController = StreamController<AudioOutput?>.broadcast();
  final _linkedController = StreamController<bool>.broadcast();

  NowPlaying? _current;
  MusicConnection _connectionState = MusicConnection.disconnected;
  AudioOutput? _output;
  bool _linked = false;

  /// The backoff timer for an automatic retry, and how many have run since
  /// the last successful connection.
  Timer? _retryTimer;
  int _retries = 0;

  /// Escalating waits between silent reconnect attempts. App Remote drops for
  /// ordinary reasons — the Spotify app was swapped out, the phone slept, the
  /// service restarted — and most of those recover on the first or second
  /// try; the tail is there so a genuinely absent player (Spotify force-quit)
  /// costs a handful of cheap attempts rather than a permanent poll. The list
  /// also bounds the run: past its end we stop and wait for the next resume
  /// (or the user's tap), because something is wrong that retrying won't fix.
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 12),
    Duration(seconds: 30),
  ];

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<ConnectionStatus>? _connectionStatusSub;

  /// The OS audio route (headphones / BT / speaker), bridged from a native
  /// platform channel. Watched for the controller's whole lifetime — the route
  /// is a system concern independent of the Spotify connection, so we don't gate
  /// it behind [connect]. Resolves to null off-device / on hosts without the
  /// native side (see [AudioRouteChannel]).
  static const _audioRoute = AudioRouteChannel();
  StreamSubscription<AudioOutput?>? _routeSub;

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

  // The Spotify App Remote SDK doesn't report the OS audio route, so it comes
  // from a native platform channel instead (AVAudioSession / AudioManager) via
  // [AudioRouteChannel]. Null on hosts without the native side.
  @override
  Stream<AudioOutput?> get output => _outputController.stream;

  @override
  AudioOutput? get currentOutput => _output;

  @override
  Stream<bool> get linked => _linkedController.stream;

  @override
  bool get isLinked => _linked;

  /// Reads this device's stored consent and, if it has one, immediately tries
  /// to reattach. This is what makes the app "already connected" when it
  /// opens over a Spotify that is already playing: no tap, no prompt — the
  /// authorization happened once, and it is still good.
  Future<void> _restoreLink() async {
    bool linked;
    try {
      linked = await _links.isLinked();
    } catch (_) {
      linked = false; // no prefs (a test host, a fresh install) = not linked
    }
    if (!linked) return;
    _setLinked(true);
    await connect();
  }

  void _setLinked(bool value) {
    if (_linked == value) return;
    _linked = value;
    if (!_linkedController.isClosed) _linkedController.add(value);
  }

  void _watchAudioRoute() {
    // Seed with the current route (so `currentOutput`/initialData is populated),
    // then follow live changes. Both are null-safe off-device.
    unawaited(_audioRoute.current().then(_setOutput));
    _routeSub = _audioRoute.changes().listen(_setOutput);
  }

  void _setOutput(AudioOutput? out) {
    _output = out;
    if (!_outputController.isClosed) _outputController.add(out);
  }

  void _setConnection(MusicConnection state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  @override
  Future<void> reconnectIfLinked() async {
    if (!_linked) return;
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    // A resume is a fresh chance, so the previous run's exhausted budget
    // shouldn't hold it back.
    _retries = 0;
    await connect();
  }

  @override
  Future<void> connect() async {
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    _retryTimer?.cancel();
    _setConnection(MusicConnection.connecting);
    try {
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: spotifyClientId,
        redirectUrl: spotifyRedirectUri,
      );
      if (!connected) {
        _failed(MusicConnection.disconnected);
        return;
      }
    } on PlatformException catch (e) {
      _failed(_mapErrorCode(e.code));
      return;
    } on MissingPluginException {
      // The native side isn't wired up on this platform (e.g. running on
      // an unsupported target) — reads the same as "can't connect" to the
      // UI, not a crash.
      _failed(MusicConnection.disconnected);
      return;
    }

    _setConnection(MusicConnection.connected);
    // Connecting IS the consent. From here the app reattaches on its own at
    // every launch and resume, and the user never sees Connect again unless
    // they explicitly disconnect.
    _retries = 0;
    _setLinked(true);
    unawaited(_links.setLinked(true).catchError((Object _) {}));

    unawaited(_playerStateSub?.cancel());
    _playerStateSub = SpotifySdk.subscribePlayerState().listen(
      (state) async {
        final track = state.track;
        if (track == null) {
          // App Remote emits track-less states transiently mid-skip. Don't
          // publish them — a one-frame "Nothing playing" flash between two
          // songs reads as breakage; the real track arrives a beat later.
          return;
        }
        // Publish the track IMMEDIATELY with whatever artwork is already
        // cached — title/artist/duration/position must never wait on an
        // artwork round-trip to the Spotify app. If artwork isn't cached,
        // fetch it out-of-band and republish (see [_fetchArtworkAndRepublish]).
        final artwork = _cachedArtworkIfAny(track);
        _current = NowPlaying(
          trackId: track.uri,
          title: track.name,
          artist: track.artist.name ?? '',
          artworkBytes: artwork,
          duration: Duration(milliseconds: track.duration),
          position: Duration(milliseconds: state.playbackPosition),
          isPaused: state.isPaused,
          // Real, observed shuffle/repeat straight from the player state, so the
          // controls reflect Spotify's truth (including changes made on another
          // device), not an optimistic local toggle. `.name` sidesteps the
          // package's two same-named `RepeatMode` types (see the import note).
          isShuffling: state.playbackOptions.isShuffling,
          repeatMode: _repeatFromName(state.playbackOptions.repeatMode.name),
          // App Remote alone can't see other Spotify Connect devices — that
          // needs the separate Web API's "available devices" endpoint, which
          // this integration doesn't call. True is a safe default until that's
          // added; a genuinely different active device would otherwise show as
          // this app having control when it doesn't.
          hasControl: true,
        );
        _nowPlayingController.add(_current);
        if (artwork == null && track.imageUri.raw.isNotEmpty) {
          unawaited(_fetchArtworkAndRepublish(track));
        }
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
        _retries = 0;
        _retryTimer?.cancel();
      } else {
        // A drop, not a decision. On a linked device this is the case the
        // whole feature exists for — Spotify was swapped out, the socket
        // died — so schedule a silent retry rather than leaving the user
        // staring at a dead strip.
        _failed(_mapErrorCode(status.errorCode));
      }
    });
  }

  /// Publishes a failed/lost connection and, where retrying could plausibly
  /// help, queues the next silent attempt.
  ///
  /// [MusicConnection.authFailed] and [MusicConnection.noSpotifyApp] are
  /// deliberately terminal: the first can put an authorization sheet in front
  /// of the user and the second cannot succeed at all, so hammering either
  /// would be worse than the dead strip. Both surface a tappable affordance
  /// instead (see `NowPlayingLozenge`) — retrying those is the user's call.
  void _failed(MusicConnection state) {
    _setConnection(state);
    if (!_linked) return;
    if (state == MusicConnection.authFailed ||
        state == MusicConnection.noSpotifyApp) {
      return;
    }
    if (_retries >= _retryDelays.length) return;
    final delay = _retryDelays[_retries++];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_connectionState == MusicConnection.connected) return;
      unawaited(connect());
    });
  }

  /// Explicit, user-initiated: this **unlinks** the device as well as closing
  /// the connection, so nothing reconnects behind the user's back after they
  /// asked it to stop.
  @override
  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _retries = 0;
    _setLinked(false);
    unawaited(_links.setLinked(false).catchError((Object _) {}));
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
  Future<void> setShuffle(bool shuffle) async {
    try {
      await SpotifySdk.setShuffle(shuffle: shuffle);
      // The new value is observed back via subscribePlayerState() (above), the
      // single source of truth the UI reacts to — same as play/pause.
    } on Exception {
      // See the swallow-our-own-errors comment above the transport controls.
    }
  }

  @override
  Future<void> setRepeat(MusicRepeatMode mode) async {
    try {
      await SpotifySdk.setRepeatMode(repeatMode: _sdkRepeat(mode));
    } on Exception {
      // See the swallow-our-own-errors comment above the transport controls.
    }
  }

  /// Domain [MusicRepeatMode] → the App Remote SDK's own repeat enum (the
  /// prefixed `sdk.RepeatMode` — see the import note). `all` is Spotify's
  /// `context`.
  static sdk.RepeatMode _sdkRepeat(MusicRepeatMode mode) => switch (mode) {
    MusicRepeatMode.off => sdk.RepeatMode.off,
    MusicRepeatMode.all => sdk.RepeatMode.context,
    MusicRepeatMode.one => sdk.RepeatMode.track,
  };

  /// The player state's repeat value, read by name so we don't have to import
  /// the package's *other* (unprefixed) `RepeatMode`. `context` is our `all`.
  static MusicRepeatMode _repeatFromName(String name) => switch (name) {
    'track' => MusicRepeatMode.one,
    'context' => MusicRepeatMode.all,
    _ => MusicRepeatMode.off,
  };

  @override
  void dispose() {
    _retryTimer?.cancel();
    _playerStateSub?.cancel();
    _connectionStatusSub?.cancel();
    _routeSub?.cancel();
    _nowPlayingController.close();
    _connectionController.close();
    _outputController.close();
    _linkedController.close();
  }

  /// Synchronous cache check — what track-change emissions use so they never
  /// block on the platform channel.
  Uint8List? _cachedArtworkIfAny(Track track) {
    final uri = track.imageUri.raw;
    if (uri.isEmpty) return null;
    return uri == _cachedArtworkTrackUri ? _cachedArtworkBytes : null;
  }

  /// Fetches artwork off the critical path and republishes — but only if this
  /// track is STILL current when the bytes land (a fast skip-past must not
  /// patch stale artwork onto a newer song).
  Future<void> _fetchArtworkAndRepublish(Track track) async {
    final bytes = await _artworkFor(track);
    if (bytes == null) return;
    final current = _current;
    if (current == null || current.trackId != track.uri) return;
    _current = current.copyWith(artworkBytes: bytes);
    _nowPlayingController.add(_current);
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
