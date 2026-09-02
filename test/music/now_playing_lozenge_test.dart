import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/music/domain/audio_output.dart';
import 'package:zivo/features/music/domain/music_connection.dart';
import 'package:zivo/features/music/domain/music_controller.dart';
import 'package:zivo/features/music/domain/now_playing.dart';
import 'package:zivo/features/music/presentation/now_playing_lozenge.dart';

/// The bottom bar's music strip is the app's ONE permanent music surface: it
/// carries the full transport while a track is live, and — once the device is
/// linked — it stays put through a dropped connection with the reconnect on
/// it, instead of vanishing and leaving no way back but a button buried in
/// Settings.
class _StubController implements MusicController {
  _StubController({
    required this.connectionState,
    this.track,
    this.deviceLinked = true,
  });

  MusicConnection connectionState;
  final NowPlaying? track;
  final bool deviceLinked;

  int connectCalls = 0;
  int previousCalls = 0;
  int nextCalls = 0;
  int pauseCalls = 0;

  @override
  Stream<NowPlaying?> get nowPlaying => Stream.value(track);

  @override
  Stream<MusicConnection> get connection => Stream.value(connectionState);

  @override
  NowPlaying? get currentNowPlaying => track;

  @override
  MusicConnection get currentConnection => connectionState;

  @override
  Stream<AudioOutput?> get output => const Stream.empty();

  @override
  AudioOutput? get currentOutput => null;

  @override
  Stream<bool> get linked => Stream.value(deviceLinked);

  @override
  bool get isLinked => deviceLinked;

  @override
  Future<void> connect() async {
    connectCalls++;
    connectionState = MusicConnection.connecting;
  }

  @override
  Future<void> reconnectIfLinked() async {
    if (deviceLinked) await connect();
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> next() async => nextCalls++;

  @override
  Future<void> previous() async => previousCalls++;

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

const _fixtureTrack = NowPlaying(
  trackId: 'spotify:track:1',
  title: 'Fixture Track',
  artist: 'Fixture Artist',
  duration: Duration(minutes: 3),
  position: Duration(seconds: 30),
  isPaused: false,
  hasControl: true,
);

Future<void> _pump(WidgetTester tester, _StubController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: NowPlayingLozenge(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a live track carries previous, play/pause and next', (
    tester,
  ) async {
    final controller = _StubController(
      connectionState: MusicConnection.connected,
      track: _fixtureTrack,
    );
    await _pump(tester, controller);

    // All three transports are present — "skip a song without opening
    // Spotify" is the whole reason the strip is in the nav bar.
    await tester.tap(find.bySemanticsLabel('Previous track'));
    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();

    expect(controller.previousCalls, 1);
    expect(controller.nextCalls, 1);
    expect(controller.pauseCalls, 1);
  });

  testWidgets(
    'a linked-but-dropped connection shows Reconnect, and tapping it connects',
    (tester) async {
      final controller = _StubController(
        connectionState: MusicConnection.disconnected,
      );
      await _pump(tester, controller);

      expect(find.text('Reconnect Spotify'), findsOneWidget);

      await tester.tap(find.text('Reconnect Spotify'));
      await tester.pump();

      expect(
        controller.connectCalls,
        1,
        reason: 'the strip IS the reconnect control, not a pointer to one',
      );
    },
  );

  testWidgets('a device that never linked is offered Connect, not Reconnect', (
    tester,
  ) async {
    final controller = _StubController(
      connectionState: MusicConnection.disconnected,
      deviceLinked: false,
    );
    await _pump(tester, controller);

    expect(find.text('Connect Spotify'), findsOneWidget);
  });

  testWidgets('an in-flight handshake says so instead of offering a tap', (
    tester,
  ) async {
    final controller = _StubController(
      connectionState: MusicConnection.connecting,
    );
    await _pump(tester, controller);

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('connected with nothing loaded reads as "Nothing playing"', (
    tester,
  ) async {
    final controller = _StubController(
      connectionState: MusicConnection.connected,
    );
    await _pump(tester, controller);

    expect(find.text('Nothing playing'), findsOneWidget);
  });

  testWidgets('the strip is always exactly the height the shell reserved', (
    tester,
  ) async {
    for (final controller in [
      _StubController(
        connectionState: MusicConnection.connected,
        track: _fixtureTrack,
      ),
      _StubController(connectionState: MusicConnection.disconnected),
      _StubController(connectionState: MusicConnection.connecting),
    ]) {
      await _pump(tester, controller);
      expect(
        tester.getSize(find.byType(NowPlayingLozenge)).height,
        kNowPlayingLozengeHeight,
        reason: 'every state must fit the one height BottomChrome reserves',
      );
    }
  });
}
