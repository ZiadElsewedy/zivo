import 'music_connection.dart';
import 'now_playing.dart';

/// The seam every music UI in this app is built against — never a concrete
/// player SDK directly. `FakeMusicController` is what the app actually runs
/// on today (see its doc comment); `SpotifyMusicController` is the real
/// binding, finished once `music_config.dart`'s `spotifyClientId` is filled
/// in.
abstract class MusicController {
  /// The current track and playback position, or null when nothing is
  /// loaded. Emits a new value on every state change reported by the
  /// underlying player (play/pause/seek/track-change) — NOT on a timer, so
  /// listeners that need a smoothly ticking clock (the scrubber, the mini
  /// bar's progress line) interpolate locally between emissions.
  Stream<NowPlaying?> get nowPlaying;

  /// The controller's connection to the underlying player. See
  /// [MusicConnection] for what each state means and how the UI should
  /// react to it.
  Stream<MusicConnection> get connection;

  /// The last value [nowPlaying] emitted, read synchronously — paired with
  /// the stream as `StreamBuilder`'s `initialData`, the same convention
  /// every other repository in this app follows, so the UI never flashes
  /// an empty state before the first stream event lands.
  NowPlaying? get currentNowPlaying;

  /// The last value [connection] emitted, read synchronously — same
  /// `initialData` role as [currentNowPlaying].
  MusicConnection get currentConnection;

  /// Starts (or retries) connecting to the underlying player. A no-op if
  /// already connected/connecting.
  Future<void> connect();

  /// Tears down the connection — [connection] emits `disconnected` and
  /// [nowPlaying] emits null.
  Future<void> disconnect();

  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();

  /// Jumps playback to [position] — the scrubber's drag-release target.
  Future<void> seek(Duration position);

  /// Seeks to the start of the current track — shorthand for
  /// `seek(Duration.zero)`, surfaced separately since "replay" is its own
  /// dedicated control in the full player, not just an extreme scrub.
  Future<void> replay();

  /// Releases whatever the implementation is holding open — a polling
  /// timer ([FakeMusicController]), a player-state subscription
  /// ([SpotifyMusicController], once wired). [AppScope]'s `music` lives for
  /// the app's process lifetime in production, but widget tests rebuild the
  /// tree (and therefore construct a fresh controller) per test — without
  /// this, `FakeMusicController`'s ticker outlives its test and trips
  /// `flutter_test`'s "timer still pending" invariant. Called from
  /// `_ZivoAppState.dispose()`.
  void dispose();
}
