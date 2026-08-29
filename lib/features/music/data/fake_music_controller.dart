import 'dart:async';
import 'dart:math';

import '../domain/audio_output.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';

/// One entry in the fake controller's playlist. No `artworkUrl` field — none
/// of the fixture tracks below have one, deliberately exercising
/// `MusicPlayerPage`'s no-artwork fallback. A real URL
/// (or bundled placeholder asset) is Ziad's call, not picked here.
class _FakeTrack {
  const _FakeTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final Duration duration;
}

/// A WORKING simulation of a music player — what every music UI in this app
/// actually runs on today (see `music_config.dart`'s `kMusicEnabled`). Holds
/// a short fake playlist and a periodic timer that advances `position`
/// while playing, so play/pause/seek/skip/replay all behave like a real
/// player rather than static mock data. Swapped for `SpotifyMusicController`
/// only once a real Client ID is wired up (see `app.dart`).
///
/// Starts already connected and playing — there's no real device/account to
/// wait on, so gating the demo behind an explicit `connect()` call would
/// just be friction. `connect()`/`disconnect()` still work (idempotent),
/// for exercising the connection-state UI itself.
class FakeMusicController implements MusicController {
  FakeMusicController() {
    _connectionController.add(MusicConnection.connected);
    _startTicker();
    _emit();
    _emitOutput();
  }

  /// An obviously-fake output device — same "unmistakably fixture, never reads
  /// as a real product" spirit as the playlist above — so the player's output
  /// row is demoable off-device (real routes need a platform channel that only
  /// runs on hardware; see `MusicController.output`). Mirrors the prototype's
  /// Bluetooth + battery case.
  static const _fixtureOutput = AudioOutput(
    name: 'Fixture Buds',
    kind: AudioOutputKind.bluetooth,
    batteryPercent: 72,
  );

  // A handful of placeholder tracks — Ziad's call whether these ship as
  // real seed content or get swapped before the flag ever flips on; picked
  // to be unmistakably fake (no real artist/track names) rather than
  // accidentally reading as a real catalog. No artwork — the lozenge /
  // `MusicPlayerPage` both already fall back to a placeholder icon, so this
  // also doubles as a check that the no-artwork path actually works.
  static const _playlist = [
    _FakeTrack(
      id: 'demo-1',
      title: 'Fixture Track One',
      artist: 'Sample Artist',
      duration: Duration(minutes: 3, seconds: 24),
    ),
    _FakeTrack(
      id: 'demo-2',
      title: 'Fixture Track Two',
      artist: 'Sample Artist',
      duration: Duration(minutes: 2, seconds: 51),
    ),
    _FakeTrack(
      id: 'demo-3',
      title: 'Fixture Track Three',
      artist: 'Another Artist',
      duration: Duration(minutes: 4, seconds: 2),
    ),
  ];

  int _index = 0;
  Duration _position = Duration.zero;
  bool _isPaused = false;
  bool _connected = true;
  bool _shuffle = false;
  MusicRepeatMode _repeatMode = MusicRepeatMode.off;
  Timer? _ticker;
  final _random = Random();

  final _nowPlayingController = StreamController<NowPlaying?>.broadcast();
  final _connectionController = StreamController<MusicConnection>.broadcast();
  final _outputController = StreamController<AudioOutput?>.broadcast();

  NowPlaying? _current;
  MusicConnection _connectionState = MusicConnection.connected;
  AudioOutput? _output;

  @override
  Stream<NowPlaying?> get nowPlaying => _nowPlayingController.stream;

  @override
  Stream<MusicConnection> get connection => _connectionController.stream;

  @override
  Stream<AudioOutput?> get output => _outputController.stream;

  @override
  NowPlaying? get currentNowPlaying => _current;

  @override
  MusicConnection get currentConnection => _connectionState;

  @override
  AudioOutput? get currentOutput => _output;

  void _emitOutput() {
    // No device when disconnected — the route belongs to the connection.
    _output = _connected ? _fixtureOutput : null;
    _outputController.add(_output);
  }

  _FakeTrack get _track => _playlist[_index];

  void _emit() {
    _current = NowPlaying(
      trackId: _track.id,
      title: _track.title,
      artist: _track.artist,
      artworkUrl: null,
      duration: _track.duration,
      position: _position,
      isPaused: _isPaused,
      hasControl: true,
      isShuffling: _shuffle,
      repeatMode: _repeatMode,
    );
    _nowPlayingController.add(_current);
  }

  void _startTicker() {
    _ticker?.cancel();
    // 250ms, not every frame — this is a data-layer fake, not a widget; the
    // UI smooths the steps between emissions itself (see
    // `MusicScrubber._resync`'s `animateTo`), same as it would against a
    // real player's own coarse state-change cadence.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_isPaused) return;
      final next = _position + const Duration(milliseconds: 250);
      if (next >= _track.duration) {
        _onNaturalEnd();
      } else {
        _position = next;
        _emit();
      }
    });
  }

  /// The current track finished on its own. Repeat-one loops it in place;
  /// otherwise the queue moves on (respecting shuffle). An explicit
  /// [next]/[previous] skip is separate — those ignore repeat-one, like a real
  /// player.
  void _onNaturalEnd() {
    if (_repeatMode == MusicRepeatMode.one) {
      _position = Duration.zero;
      _emit();
    } else {
      _goToNextTrack();
    }
  }

  void _goToNextTrack() {
    _index = (_shuffle && _playlist.length > 1)
        // A different track at random — never the current one, so it always
        // audibly progresses.
        ? (_index + 1 + _random.nextInt(_playlist.length - 1)) % _playlist.length
        : (_index + 1) % _playlist.length;
    _position = Duration.zero;
    _emit();
  }

  @override
  Future<void> connect() async {
    if (_connected) return;
    _connectionState = MusicConnection.connecting;
    _connectionController.add(_connectionState);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connected = true;
    _connectionState = MusicConnection.connected;
    _connectionController.add(_connectionState);
    _startTicker();
    _emit();
    _emitOutput();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _ticker?.cancel();
    _connectionState = MusicConnection.disconnected;
    _connectionController.add(_connectionState);
    _current = null;
    _nowPlayingController.add(null);
    _emitOutput();
  }

  @override
  Future<void> play() async {
    if (!_connected) return;
    _isPaused = false;
    _emit();
  }

  @override
  Future<void> pause() async {
    if (!_connected) return;
    _isPaused = true;
    _emit();
  }

  @override
  Future<void> next() async {
    if (!_connected) return;
    _goToNextTrack();
  }

  @override
  Future<void> previous() async {
    if (!_connected) return;
    // A real player restarts the current track past a few seconds in,
    // rather than always hopping back a track — mirrored here for a
    // realistic feel.
    if (_position > const Duration(seconds: 3)) {
      _position = Duration.zero;
    } else {
      _index = (_index - 1 + _playlist.length) % _playlist.length;
      _position = Duration.zero;
    }
    _emit();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_connected) return;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _track.duration ? _track.duration : position);
    _position = clamped;
    _emit();
  }

  @override
  Future<void> replay() => seek(Duration.zero);

  @override
  Future<void> setShuffle(bool shuffle) async {
    if (!_connected) return;
    _shuffle = shuffle;
    _emit();
  }

  @override
  Future<void> setRepeat(MusicRepeatMode mode) async {
    if (!_connected) return;
    _repeatMode = mode;
    _emit();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nowPlayingController.close();
    _connectionController.close();
    _outputController.close();
  }
}
