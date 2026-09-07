import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
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
/// entirely on-device — the SDK handles the PKCE exchange internally given
/// just a `clientId` + `redirectUrl`.
///
/// App Remote requires the Spotify app installed + a Premium account, and
/// does NOT work on the iOS Simulator (real device only). The dashboard app
/// must also be in "Development mode" with the testing account added under
/// User Management, or auth fails outright.
///
/// ## Sync automatically; never launch automatically
///
/// **The app attaches to a Spotify that is already playing. It never opens
/// one that isn't.** That distinction is the whole shape of this class, and
/// it is not decoration — it is the difference between two SDK calls that
/// both read as "connect":
///
/// - [_authorize] — `getAccessToken` → the native `authorizeAndPlayURI`.
///   Opens the Spotify app and starts playback. Only ever runs from a user's
///   own tap on Connect.
/// - [_attach] — `connectToSpotifyRemote(accessToken:)` → the native
///   `SPTAppRemote.connect`. Attaches to a running Spotify and **fails
///   harmlessly when Spotify isn't running** (the header is explicit: "If the
///   Spotify app is not running you will need to use authorizeAndPlayURI: to
///   wake it up"). Every automatic attempt — launch, resume, the one retry —
///   goes through this and only this.
///
/// The app used to call the first one automatically, so opening ZIVO dragged
/// Spotify open and started music the user hadn't asked for, and quitting
/// Spotify just made it come back. Silent attach needs a token, which is why
/// [SpotifyLinkStore] keeps one; with no token stored, an automatic attempt
/// does nothing at all rather than falling back to the launching path.
///
/// Android has no such split: its `connectToSpotify` ignores the token and
/// binds to the Spotify service without forcing playback or foregrounding the
/// app, so [_attach] and [_authorize] are the same call there. See
/// [_silentAttachNeedsToken].
class SpotifyMusicController implements MusicController {
  SpotifyMusicController({SpotifyLinkStore? links, bool? silentAttachNeedsToken})
    : _links = links ?? SpotifyLinkStore(),
      _silentAttachNeedsToken =
          silentAttachNeedsToken ?? defaultTargetPlatform == TargetPlatform.iOS {
    _watchAudioRoute();
    _watchConnectionStatus();
    unawaited(_restoreLink());
  }

  final SpotifyLinkStore _links;

  /// Whether a silent [_attach] on this platform needs a stored access token —
  /// true on iOS, where the tokenless call is the one that opens Spotify and
  /// starts playing. It doubles as "the user's Connect must go through
  /// `getAccessToken` so we capture a token for next time", because those are
  /// two faces of the same platform fact.
  ///
  /// Injectable so a test can exercise either platform's path without a device
  /// (and so `defaultTargetPlatform` — macOS under `flutter test` — doesn't
  /// silently pick the Android branch).
  final bool _silentAttachNeedsToken;

  final _nowPlayingController = StreamController<NowPlaying?>.broadcast();
  final _connectionController = StreamController<MusicConnection>.broadcast();
  final _outputController = StreamController<AudioOutput?>.broadcast();
  final _linkedController = StreamController<bool>.broadcast();

  NowPlaying? _current;
  MusicConnection _connectionState = MusicConnection.disconnected;
  AudioOutput? _output;
  bool _linked = false;

  /// The App Remote access token, restored from [SpotifyLinkStore] at launch
  /// and refreshed by every user-initiated [connect]. Null means the only way
  /// in on iOS is the authorizing call — so nothing automatic is attempted.
  String? _token;

  /// The single silent retry after a drop, and whether it has been spent since
  /// the last successful connection.
  Timer? _retryTimer;
  bool _retried = false;

  /// One short retry, then stop. App Remote drops for ordinary reasons — the
  /// Spotify app was swapped out, the socket died on resume — and those
  /// recover immediately or not at all. The old escalating chain (2s → 5s →
  /// 12s → 30s) existed because each attempt could re-launch Spotify and
  /// therefore had to be worth the interruption; a silent attach costs
  /// nothing, but it also can't conjure a player that the user has closed.
  /// When the user quits Spotify, the app stops syncing and stays stopped —
  /// the next attempt is the next resume, or their tap.
  static const _retryDelay = Duration(seconds: 2);

  /// How long a user-initiated [_authorize] may sit unresolved before we call
  /// it dead.
  ///
  /// The native `authorizeAndPlayURI` reports "Spotify isn't installed" to a
  /// callback the `getAccessToken` path never set (a `spotify_sdk` 3.0.2 bug:
  /// it answers `connectionResult`, which only the `connectToSpotify` path
  /// assigns), so that one case hangs instead of failing. Every other outcome
  /// — authorized, refused, connection error — resolves the future or arrives
  /// on the connection-status channel. Hence the timeout, and hence
  /// [MusicConnection.noSpotifyApp] as its verdict: a missing Spotify app is
  /// the only thing that realistically reaches it. If it ever fires on a user
  /// who simply lingered in Spotify, the status channel corrects it the moment
  /// they come back — [_watchConnectionStatus] runs for the controller's whole
  /// life, not just inside a connect.
  static const _authorizeTimeout = Duration(seconds: 30);

  /// How long a silent [_attach] may sit unresolved. The native side is
  /// supposed to fail its delegate promptly when Spotify isn't running, and in
  /// practice does — this only exists so a handshake that answers neither way
  /// can't strand the strip on "Connecting…" forever.
  static const _attachTimeout = Duration(seconds: 15);

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

  /// Reads this device's stored consent and token and, if it has both, tries a
  /// silent attach. This is what makes the app "already connected" when it
  /// opens over a Spotify that is already playing: no tap, no prompt, and —
  /// critically — no Spotify appearing on screen if it wasn't already running.
  Future<void> _restoreLink() async {
    SpotifyLink link;
    try {
      link = await _links.read();
    } catch (_) {
      link = SpotifyLink.none; // no prefs (a test host, a fresh install)
    }
    _token = link.accessToken;
    if (!link.linked) return;
    _setLinked(true);
    await _attach();
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
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_connectionController.isClosed) _connectionController.add(state);
  }

  /// Watches the App Remote connection for the controller's whole lifetime,
  /// rather than only from inside a successful connect.
  ///
  /// This channel is the single truth about connectedness: it reports the
  /// handshake, and it reports the later drop when the user quits Spotify. It
  /// is registered natively at plugin attach on both platforms, so subscribing
  /// before the first connect is safe — and it means an attach that resolves
  /// late (or a state we misread) is corrected rather than stuck.
  void _watchConnectionStatus() {
    try {
      _connectionStatusSub = SpotifySdk.subscribeConnectionStatus().listen(
        (status) {
          if (status.connected) {
            _onConnected();
          } else {
            // A drop, not a decision — the Spotify app was swapped out or
            // quit. Publish it and let [_failed] decide whether one quiet
            // retry is worth trying.
            _failed(_mapErrorCode(status.errorCode));
          }
        },
        // A host with no native side (the simulator, a test) errors on listen;
        // the controller just stays disconnected, same as it always did.
        onError: (Object _) {},
      );
    } on Exception {
      // Same: nothing to watch here, and nothing to report.
    }
  }

  @override
  Future<void> reconnectIfLinked() async {
    if (!_linked) return;
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    // A resume is a fresh chance, so the previous run's spent retry shouldn't
    // hold it back.
    _retried = false;
    await _attach();
  }

  /// **User-initiated.** The one path allowed to open Spotify and ask for
  /// authorization — every automatic attempt goes through [_attach] instead.
  ///
  /// Even here, attaching is tried first when there's a token to try it with.
  /// The most common tap on this is *Reconnect* after an ordinary drop, and if
  /// Spotify is still running that costs one silent handshake instead of a
  /// round trip out to Spotify's UI and back. Only when there is nothing to
  /// attach to does the user's tap become an authorization.
  @override
  Future<void> connect() async {
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    _retryTimer?.cancel();
    _retried = false;
    if (!_silentAttachNeedsToken) {
      await _attach(force: true);
      return;
    }
    if (_token != null) {
      await _attach();
      if (_connectionState == MusicConnection.connected) return;
      // Authorizing can't install Spotify; don't spend 30s finding that out.
      if (_connectionState == MusicConnection.noSpotifyApp) return;
      // The attach failed, so we're about to authorize instead — the queued
      // silent retry would only race that.
      _retryTimer?.cancel();
      _retried = false;
    }
    await _authorize();
  }

  /// The authorizing connect: opens Spotify, authorizes, and hands back the
  /// access token that makes every later attach silent.
  ///
  /// `getAccessToken` is used rather than `connectToSpotifyRemote` because it
  /// is the only call in `spotify_sdk` that *returns* the token — and it
  /// resolves from the native `appRemoteDidEstablishConnection`, so a token in
  /// hand is itself proof the App Remote connection is up. That's why success
  /// goes straight to [_onConnected] instead of waiting on the status channel.
  Future<void> _authorize() async {
    _setConnection(MusicConnection.connecting);
    String token;
    try {
      token = await SpotifySdk.getAccessToken(
        clientId: spotifyClientId,
        redirectUrl: spotifyRedirectUri,
      ).timeout(_authorizeTimeout);
    } on TimeoutException {
      _failed(MusicConnection.noSpotifyApp); // see [_authorizeTimeout]
      return;
    } on PlatformException catch (e) {
      _failed(_mapErrorCode(e.code));
      return;
    } on MissingPluginException {
      // The native side isn't wired up on this platform — reads the same as
      // "can't connect" to the UI, not a crash.
      _failed(MusicConnection.disconnected);
      return;
    }
    // `getAccessToken` stringifies whatever the native side hands back, so an
    // absent token arrives as the word "null" rather than as an error.
    if (token.isEmpty || token == 'null') {
      _failed(MusicConnection.authFailed);
      return;
    }
    _token = token;
    unawaited(_links.setAccessToken(token).catchError((Object _) {}));
    _onConnected();
  }

  /// The silent attach: joins a Spotify that is already running, and fails
  /// without a trace when there is nothing to join.
  ///
  /// [force] marks the user's own Connect on a platform where attach and
  /// authorize are the same call (Android), so it may run with no token.
  Future<void> _attach({bool force = false}) async {
    if (_connectionState == MusicConnection.connecting ||
        _connectionState == MusicConnection.connected) {
      return;
    }
    final token = _token;
    if (_silentAttachNeedsToken && token == null && !force) {
      // Nothing to attach with, and the alternative would put Spotify on
      // screen. Stay where we are — the strip offers Connect, and that tap is
      // the user's to make.
      _setConnection(MusicConnection.disconnected);
      return;
    }
    _retryTimer?.cancel();
    _setConnection(MusicConnection.connecting);
    try {
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: spotifyClientId,
        redirectUrl: spotifyRedirectUri,
        accessToken: token,
      ).timeout(_attachTimeout);
      if (!connected) {
        _failed(MusicConnection.disconnected);
        return;
      }
    } on TimeoutException {
      // Nothing answered. Don't sit on "Connecting…" — call it down and let
      // the status channel promote us if the handshake lands late.
      _failed(MusicConnection.disconnected);
      return;
    } on PlatformException catch (e) {
      _failed(_mapErrorCode(e.code));
      return;
    } on MissingPluginException {
      _failed(MusicConnection.disconnected);
      return;
    }
    _onConnected();
  }

  /// Everything that follows a live connection, from either path and from the
  /// status channel — so it has to be idempotent.
  void _onConnected() {
    _retryTimer?.cancel();
    _retried = false;
    _setConnection(MusicConnection.connected);
    // Connecting IS the consent. From here the app reattaches on its own at
    // every launch and resume — silently — and the user never sees Connect
    // again unless they explicitly disconnect or the token lapses.
    _setLinked(true);
    unawaited(_links.setLinked(true).catchError((Object _) {}));
    _subscribePlayerState();
  }

  void _subscribePlayerState() {
    if (_playerStateSub != null) return; // already live; don't stack listeners
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
        if (!_nowPlayingController.isClosed) _nowPlayingController.add(_current);
        if (artwork == null && track.imageUri.raw.isNotEmpty) {
          unawaited(_fetchArtworkAndRepublish(track));
        }
      },
      onError: (Object error) {
        if (error is PlatformException) _failed(_mapErrorCode(error.code));
      },
    );
  }

  /// Publishes a failed or lost connection, drops the track it was carrying,
  /// and — where a silent retry could plausibly help — queues exactly one.
  ///
  /// [MusicConnection.authFailed] and [MusicConnection.noSpotifyApp] never
  /// retry: the first needs a fresh authorization (which is the user's tap to
  /// give, since granting one puts Spotify on screen) and the second cannot
  /// succeed at all. Both surface a tappable affordance instead — see
  /// `NowPlayingLozenge`.
  void _failed(MusicConnection state) {
    unawaited(_playerStateSub?.cancel());
    _playerStateSub = null;
    if (_current != null) {
      _current = null;
      if (!_nowPlayingController.isClosed) _nowPlayingController.add(null);
    }
    _setConnection(state);
    if (!_linked || _retried) return;
    if (state == MusicConnection.authFailed ||
        state == MusicConnection.noSpotifyApp) {
      return;
    }
    // No token means the retry would be a no-op on iOS; don't schedule one.
    if (_silentAttachNeedsToken && _token == null) return;
    _retried = true;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (_connectionState == MusicConnection.connected) return;
      unawaited(_attach());
    });
  }

  /// Explicit, user-initiated: this **unlinks** the device as well as closing
  /// the connection — consent and stored token both go — so nothing
  /// reconnects behind the user's back after they asked it to stop.
  @override
  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _retried = false;
    _token = null;
    _setLinked(false);
    unawaited(_links.clear().catchError((Object _) {}));
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    try {
      await SpotifySdk.disconnect();
    } on Exception {
      // Best-effort — we're tearing down our own state regardless.
    }
    _current = null;
    if (!_nowPlayingController.isClosed) _nowPlayingController.add(null);
    _setConnection(MusicConnection.disconnected);
  }

  // The four controls below swallow their own errors deliberately: a stale
  // connection failing here will already have been (or will shortly be)
  // caught by the `subscribeConnectionStatus()` listener in
  // [_watchConnectionStatus], which is the single source of truth the UI
  // reacts to — duplicating that reaction per-control would just race it.

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
    if (!_nowPlayingController.isClosed) _nowPlayingController.add(_current);
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
  /// Everything unrecognised — including iOS's numeric `SPTError` codes, which
  /// is what a silent attach against a *closed* Spotify comes back as — falls
  /// to [MusicConnection.disconnected]. That is the right landing spot: the
  /// strip reads "Reconnect Spotify" and waits for a tap.
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
