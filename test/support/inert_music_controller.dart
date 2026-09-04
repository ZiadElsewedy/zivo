import 'package:zivo/features/music/domain/audio_output.dart';
import 'package:zivo/features/music/domain/music_connection.dart';
import 'package:zivo/features/music/domain/music_controller.dart';
import 'package:zivo/features/music/domain/now_playing.dart';

/// `wrapWithScope`'s default [MusicController] — deliberately inert (stays
/// `disconnected`, never emits a track, every method a no-op) rather than
/// `FakeMusicController`. That one starts a real `Timer.periodic` on
/// construction (see its doc comment) meant for the app's own demo runtime;
/// giving every one of the ~30 `wrapWithScope` call sites a fresh ticking
/// instance with no `dispose()` hook available would leak a pending timer
/// past each test's teardown (`flutter_test`'s "timer still pending"
/// invariant — the exact bug `app.dart`'s `_ZivoAppState.dispose()` exists
/// to avoid for the real app). Since the now-playing lozenge only ever mounts once
/// connected, staying `disconnected` also means it renders nothing —
/// existing tests that don't care about music see no new UI.
///
/// A test that DOES want to exercise music UI should pass its own
/// `music: FakeMusicController()` (and `addTearDown` its disposal) rather
/// than relying on this default.
class InertMusicController implements MusicController {
  @override
  Stream<NowPlaying?> get nowPlaying => const Stream.empty();

  @override
  Stream<MusicConnection> get connection => const Stream.empty();

  @override
  NowPlaying? get currentNowPlaying => null;

  @override
  MusicConnection get currentConnection => MusicConnection.disconnected;

  @override
  Stream<AudioOutput?> get output => const Stream.empty();

  @override
  AudioOutput? get currentOutput => null;

  /// Never linked, so nothing auto-connects and no music chrome mounts —
  /// see the class doc.
  @override
  Stream<bool> get linked => const Stream.empty();

  @override
  bool get isLinked => false;

  @override
  Future<void> reconnectIfLinked() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> replay() async {}

  @override
  Future<void> setShuffle(bool shuffle) async {}

  @override
  Future<void> setRepeat(MusicRepeatMode mode) async {}

  @override
  void dispose() {}
}
