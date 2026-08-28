import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/core/widgets/train_chrome.dart';
import 'package:zivo/features/music/data/fake_music_controller.dart';
import 'package:zivo/features/music/domain/now_playing.dart';
import 'package:zivo/features/music/presentation/music_player_page.dart';

/// Coverage for the immersive Now Playing screen. `FakeMusicController` starts
/// connected + playing with an artwork-less fixture track, so this also
/// exercises the no-cover fallback (neutral ground + green default neon) — the
/// path with no real Spotify device to lean on.
///
/// Two harness details worth knowing:
/// * The ambient glow and the Spotify equalizer animate forever, so this test
///   pumps a bounded duration and NEVER `pumpAndSettle` (which would hang).
/// * `FakeMusicController` owns a real periodic ticker; it must be disposed
///   inside the test body (a `finally`), because the "no pending timers"
///   invariant runs before `addTearDown` callbacks do.
void main() {
  testWidgets(
    'renders the track, Spotify branding and transport without overflow',
    (tester) async {
      final music = FakeMusicController();
      try {
        await tester.pumpWidget(
          MaterialApp(home: MusicPlayerPage(controller: music)),
        );
        // Long enough for every RiseIn stagger timer to have fired; short
        // enough that we don't wait on the (endless) glow animation.
        await tester.pump(const Duration(milliseconds: 300));

        // The fixture track from FakeMusicController.
        expect(find.text('Fixture Track One'), findsOneWidget);
        expect(find.text('Sample Artist'), findsOneWidget);

        // Spotify is clearly attributed as the source.
        expect(find.text('SPOTIFY'), findsOneWidget);
        expect(find.text('NOW PLAYING'), findsOneWidget);

        // No cover on the fixture → the placeholder note icon stands in.
        expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

        // Playing → the primary control shows the pause glyph (the one ember
        // action rendered, and proof the transport row laid out).
        expect(find.byType(TrainPauseGlyph), findsOneWidget);

        // The output-device row renders the fixture Bluetooth device + battery.
        expect(find.text('Fixture Buds'), findsOneWidget);
        expect(find.text('72%'), findsOneWidget);
        expect(find.byIcon(AppIcons.bluetooth), findsOneWidget);

        // Building + laying out the single-scroll player raised nothing (no
        // overflow, no missing-Material, no intrinsic-dimension crash).
        expect(tester.takeException(), isNull);
      } finally {
        music.dispose();
      }
    },
  );

  // The transport's shuffle/repeat are NOT local UI toggles — each tap requests
  // the change through the controller and the new value flows back on
  // `nowPlaying` (same contract as play/pause). A tall viewport keeps the whole
  // single-scroll player on-screen so the controls are tappable without
  // scrolling first.
  testWidgets(
    'shuffle control drives the controller and reflects its state',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      final music = FakeMusicController();
      try {
        await tester.pumpWidget(
          MaterialApp(home: MusicPlayerPage(controller: music)),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Starts off.
        expect(music.currentNowPlaying!.isShuffling, isFalse);
        expect(find.byIcon(AppIcons.shuffle), findsOneWidget);

        await tester.tap(find.byIcon(AppIcons.shuffle));
        await tester.pump(const Duration(milliseconds: 60));

        // The tap turned shuffle on, observed back through the controller.
        expect(music.currentNowPlaying!.isShuffling, isTrue);

        // Tapping again turns it back off.
        await tester.tap(find.byIcon(AppIcons.shuffle));
        await tester.pump(const Duration(milliseconds: 60));
        expect(music.currentNowPlaying!.isShuffling, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        music.dispose();
        tester.view.reset();
      }
    },
  );

  testWidgets(
    'repeat control cycles off → all → one → off with the glyph swap',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      final music = FakeMusicController();
      try {
        await tester.pumpWidget(
          MaterialApp(home: MusicPlayerPage(controller: music)),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Off → the plain repeat glyph, no repeat-one glyph anywhere.
        expect(music.currentNowPlaying!.repeatMode, MusicRepeatMode.off);
        expect(find.byIcon(AppIcons.repeat), findsOneWidget);
        expect(find.byIcon(AppIcons.repeatOne), findsNothing);

        // → all (still the plain glyph, now the active state).
        await tester.tap(find.byIcon(AppIcons.repeat));
        await tester.pump(const Duration(milliseconds: 60));
        expect(music.currentNowPlaying!.repeatMode, MusicRepeatMode.all);

        // → one (the repeat-one glyph swaps in for the plain one).
        await tester.tap(find.byIcon(AppIcons.repeat));
        await tester.pump(const Duration(milliseconds: 60));
        expect(music.currentNowPlaying!.repeatMode, MusicRepeatMode.one);
        expect(find.byIcon(AppIcons.repeatOne), findsOneWidget);
        expect(find.byIcon(AppIcons.repeat), findsNothing);

        // → off (back to the plain glyph).
        await tester.tap(find.byIcon(AppIcons.repeatOne));
        await tester.pump(const Duration(milliseconds: 60));
        expect(music.currentNowPlaying!.repeatMode, MusicRepeatMode.off);
        expect(find.byIcon(AppIcons.repeat), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        music.dispose();
        tester.view.reset();
      }
    },
  );
}
