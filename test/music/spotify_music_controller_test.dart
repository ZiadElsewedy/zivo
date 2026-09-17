import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/music/data/spotify_link_store.dart';
import 'package:zivo/features/music/data/spotify_music_controller.dart';
import 'package:zivo/features/music/domain/music_connection.dart';

/// The one rule this controller exists to keep: **it syncs with Spotify, it
/// never launches it.**
///
/// `spotify_sdk` hides two very different things behind the word "connect".
/// `getAccessToken` opens the Spotify app and starts playback;
/// `connectToSpotify` with an access token attaches to a Spotify that is
/// already running and fails harmlessly when there isn't one. Automatic
/// attempts — launch, resume, retry — are only ever allowed the second. These
/// tests watch the actual platform channel, because the whole bug was that
/// both spellings looked identical from Dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sdkChannel = MethodChannel('spotify_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Answers an event channel's listen/cancel so subscribing doesn't error.
  void stubEventChannel(String name) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }

  /// Pushes one connection-status event, as the native side would.
  Future<void> emitConnectionStatus(String json) => messenger
      .handlePlatformMessage(
        'connection_status_subscription',
        const StandardMethodCodec().encodeSuccessEnvelope(json),
        (_) {},
      );

  /// A minimal but complete player-state JSON, as the SDK's `PlayerState`
  /// decoder expects it — one track at [positionMs].
  String playerStateJson({
    required int positionMs,
    bool isPaused = false,
    String uri = 'spotify:track:abc',
  }) => jsonEncode({
    'track': {
      'album': {'name': 'Album', 'uri': 'spotify:album:x'},
      'artist': {'name': 'Artist', 'uri': 'spotify:artist:x'},
      'artists': <Map<String, dynamic>>[],
      'duration_ms': 200000,
      'image_id': {'raw': ''},
      'is_episode': false,
      'is_podcast': false,
      'name': 'Song',
      'uri': uri,
      'linked_from_uri': null,
    },
    'is_paused': isPaused,
    'playback_speed': 1.0,
    'playback_position': positionMs,
    'playback_options': {'shuffle': false, 'repeat': 0},
    'playback_restrictions': {
      'can_skip_next': true,
      'can_skip_prev': true,
      'can_repeat_track': true,
      'can_repeat_context': true,
      'can_toggle_shuffle': true,
      'can_seek': true,
    },
  });

  /// Pushes one player-state event, as the native side would.
  Future<void> emitPlayerState(String json) => messenger.handlePlatformMessage(
    'player_state_subscription',
    const StandardMethodCodec().encodeSuccessEnvelope(json),
    (_) {},
  );

  setUp(() {
    calls = [];
    stubEventChannel('connection_status_subscription');
    stubEventChannel('player_state_subscription');
    messenger.setMockMethodCallHandler(sdkChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'connectToSpotify' => true,
        'getAccessToken' => 'fresh-token',
        'disconnectFromSpotify' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(sdkChannel, null);
    stubEventChannel('connection_status_subscription');
    stubEventChannel('player_state_subscription');
  });

  /// Builds a controller pinned to the iOS split (attach needs a token), which
  /// is the platform the launching bug lived on — `defaultTargetPlatform` under
  /// `flutter test` is macOS and would otherwise take the Android branch.
  SpotifyMusicController controller() =>
      SpotifyMusicController(silentAttachNeedsToken: true);

  group('automatic attempts', () {
    test('a linked device with no token attempts nothing at all', () async {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
      });
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();

      expect(
        calls.map((c) => c.method),
        isNot(contains('getAccessToken')),
        reason: 'launching Spotify is never automatic',
      );
      expect(calls.map((c) => c.method), isNot(contains('connectToSpotify')));
      expect(music.currentConnection, MusicConnection.disconnected);
      expect(music.isLinked, isTrue, reason: 'still linked, just not attached');
    });

    test('a linked device with a token attaches silently, with it', () async {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
        'zivo.spotify.access_token': 'stored-token',
      });
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();

      final attach = calls.singleWhere((c) => c.method == 'connectToSpotify');
      expect(
        (attach.arguments as Map)['accessToken'],
        'stored-token',
        reason: 'the token is what makes it SPTAppRemote.connect, not '
            'authorizeAndPlayURI',
      );
      expect(calls.map((c) => c.method), isNot(contains('getAccessToken')));
      expect(music.currentConnection, MusicConnection.connected);
    });

    test('an unlinked device attempts nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();

      expect(calls, isEmpty);
      expect(music.isLinked, isFalse);
    });

    test('a resume on a linked device re-attaches silently', () async {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
        'zivo.spotify.access_token': 'stored-token',
      });
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();

      // Spotify goes away: the native side reports the drop.
      await emitConnectionStatus('{"connected": false}');
      await pumpEventQueue();
      expect(music.currentConnection, MusicConnection.disconnected);
      expect(music.currentNowPlaying, isNull);

      calls.clear();
      await music.reconnectIfLinked();
      expect(calls.map((c) => c.method), ['connectToSpotify']);
    });
  });

  group('keeping the timeline in sync', () {
    // The App Remote player-state stream fires on discrete events, not as a
    // position clock, so the UI only interpolates the playhead between events —
    // and it freezes while the app is backgrounded. These cover the reconcile
    // that re-anchors it from Spotify's real position without a pause/play.

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
        'zivo.spotify.access_token': 'stored-token',
      });
    });

    Future<SpotifyMusicController> connectedPlaying(int positionMs) async {
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();
      expect(music.currentConnection, MusicConnection.connected);
      await emitPlayerState(playerStateJson(positionMs: positionMs));
      await pumpEventQueue();
      expect(music.currentNowPlaying?.position.inMilliseconds, positionMs);
      return music;
    }

    test('a resume re-anchors a frozen playhead from the live position',
        () async {
      final music = await connectedPlaying(10000);

      // Spotify is really at 1:00 now; our interpolation is stuck near 0:10.
      messenger.setMockMethodCallHandler(sdkChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getPlayerState' => playerStateJson(positionMs: 60000),
          'connectToSpotify' => true,
          _ => null,
        };
      });

      calls.clear();
      await music.reconnectIfLinked(); // the app came back to the foreground
      await pumpEventQueue();

      expect(calls.map((c) => c.method), contains('getPlayerState'));
      expect(
        music.currentNowPlaying?.position.inMilliseconds,
        60000,
        reason: 'the playhead snapped to Spotify\'s real position, no pause/play',
      );
    });

    test('an in-sync playhead is left alone — no needless re-publish',
        () async {
      final music = await connectedPlaying(10000);
      var emissions = 0;
      final sub = music.nowPlaying.listen((_) => emissions++);
      addTearDown(sub.cancel);

      // Spotify reports essentially where we already are (within jitter).
      messenger.setMockMethodCallHandler(sdkChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getPlayerState' => playerStateJson(positionMs: 10200),
          _ => null,
        };
      });

      calls.clear();
      await music.reconnectIfLinked();
      await pumpEventQueue();

      expect(calls.map((c) => c.method), contains('getPlayerState'));
      expect(emissions, 0, reason: 'no drift → no rebuild');
      expect(music.currentNowPlaying?.position.inMilliseconds, 10000);
    });

    test('the periodic reconcile corrects drift while playing', () {
      fakeAsync((async) {
        final music = controller();
        addTearDown(music.dispose);
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(music.currentConnection, MusicConnection.connected);

        unawaited(emitPlayerState(playerStateJson(positionMs: 10000)));
        async.flushMicrotasks();
        expect(music.currentNowPlaying?.position.inMilliseconds, 10000);

        messenger.setMockMethodCallHandler(sdkChannel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getPlayerState' => playerStateJson(positionMs: 90000),
            _ => null,
          };
        });

        calls.clear();
        // No player event ever fires — only the reconcile poll runs.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(calls.map((c) => c.method), contains('getPlayerState'));
        expect(music.currentNowPlaying?.position.inMilliseconds, 90000);
      });
    });
  });

  group('the user tapping Connect', () {
    test('authorizes when there is no token, and keeps the one it gets',
        () async {
      SharedPreferences.setMockInitialValues({});
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();

      await music.connect();
      expect(calls.map((c) => c.method), ['getAccessToken']);
      expect(music.currentConnection, MusicConnection.connected);
      expect(music.isLinked, isTrue);

      expect(await SpotifyLinkStore().read(), _link('fresh-token'));
    });

    test('tries a silent attach first when it holds a token', () async {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
        'zivo.spotify.access_token': 'stored-token',
      });
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();
      await emitConnectionStatus('{"connected": false}');
      await pumpEventQueue();

      calls.clear();
      await music.connect();
      expect(
        calls.map((c) => c.method),
        ['connectToSpotify'],
        reason: 'Spotify was still running — no trip out to its UI needed',
      );
    });

    test('falls back to authorizing when the silent attach fails', () async {
      SharedPreferences.setMockInitialValues({
        'zivo.spotify.device_linked': true,
        'zivo.spotify.access_token': 'stale-token',
      });
      messenger.setMockMethodCallHandler(sdkChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          // Spotify isn't running: SPTAppRemote.connect can't reach it.
          'connectToSpotify' => throw PlatformException(code: '-1001'),
          'getAccessToken' => 'fresh-token',
          'disconnectFromSpotify' => true,
          _ => null,
        };
      });
      final music = controller();
      addTearDown(music.dispose);
      await pumpEventQueue();
      expect(music.currentConnection, MusicConnection.disconnected);

      calls.clear();
      await music.connect();
      expect(calls.map((c) => c.method), ['connectToSpotify', 'getAccessToken']);
      expect(music.currentConnection, MusicConnection.connected);
    });
  });

  test('disconnect erases the token, so the next launch attempts nothing',
      () async {
    SharedPreferences.setMockInitialValues({
      'zivo.spotify.device_linked': true,
      'zivo.spotify.access_token': 'stored-token',
    });
    final music = controller();
    addTearDown(music.dispose);
    await pumpEventQueue();

    await music.disconnect();
    expect(await SpotifyLinkStore().read(), _link(null, linked: false));

    calls.clear();
    final next = controller();
    addTearDown(next.dispose);
    await pumpEventQueue();
    expect(calls, isEmpty);
  });
}

Matcher _link(String? token, {bool linked = true}) => isA<SpotifyLink>()
    .having((l) => l.linked, 'linked', linked)
    .having((l) => l.accessToken, 'accessToken', token);
