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
