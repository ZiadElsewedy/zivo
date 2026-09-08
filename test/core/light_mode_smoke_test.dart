import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';
import 'package:zivo/features/moments/presentation/pages/moments_timeline_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_progress_page.dart';
import 'package:zivo/features/workout/presentation/widgets/live_session/rest_ring.dart';

import '../support/skin_contrast.dart';
import '../support/test_app.dart';

/// The failure mode light mode actually has is not "ugly", it is
/// **invisible**: one colour that stayed a literal, or a `static` that cached
/// the dark skin, and a line of near-white type is now sitting on paper.
///
/// So this renders real screens on the light skin and reads the resolved ink
/// off every piece of text on them. The floor is deliberately near the bottom
/// — this is looking for text that has all but vanished, not policing the
/// contrast ladder (`zivo_palette_test.dart` does that against the tokens).
void main() {
  const ground = ZivoPalette.light;

  setUp(ZivoTheme.resetForTesting);
  tearDown(ZivoTheme.resetForTesting);

  /// Builds [page] **in dark first, then switches to light** — the sequence
  /// the app actually goes through, because it launches on dark and the user
  /// changes it from Settings. Rendering straight into light would hide
  /// exactly the bugs that matter: a `static` that cached the first skin it
  /// saw, and a `const` screen whose element is skipped on the rebuild.
  /// [settle] false for a page carrying an animation that never ends — the
  /// rest ring breathes for as long as it is on screen, and `pumpAndSettle`
  /// waits for a still frame that never comes. Two pumps are enough there:
  /// one to build, one to pick up the post-frame repaint.
  Future<void> pumpThenFlipToLight(
    WidgetTester tester,
    Widget page, {
    bool settle = true,
  }) async {
    Future<void> advance() async {
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pumpWidget(wrapWithScope(page, brightness: Brightness.dark));
    await advance();
    await tester.pumpWidget(wrapWithScope(page, brightness: Brightness.light));
    await advance();
  }

  testWidgets('the Hub reads on paper', (tester) async {
    await pumpThenFlipToLight(tester, const HubPage());
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, ground: ground.base, screen: 'Hub');
  });

  testWidgets('Settings reads on paper', (tester) async {
    await pumpThenFlipToLight(tester, const SettingsPage());
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, ground: ground.base, screen: 'Settings');
  });

  testWidgets('a chart screen reads on paper', (tester) async {
    // Charts are where a skin usually breaks first: axis labels and grid
    // rules are the quietest ink on any screen.
    await pumpThenFlipToLight(tester, const WorkoutProgressPage());
    expect(tester.takeException(), isNull);
    expectNothingVanishes(
      tester,
      ground: ground.base,
      screen: 'Workout progress',
    );
  });

  testWidgets('the rest ring\'s countdown reads on paper', (tester) async {
    // The screen you stare at mid-set, and where the first light build put a
    // near-white numeral on a white ring: its two styles were `static final`,
    // so they held whichever skin the app drew first.
    await pumpThenFlipToLight(
      tester,
      const Scaffold(
        body: Center(
          child: RestRing(
            remaining: Duration(minutes: 1, seconds: 27),
            total: 90,
            // The ring breathes forever, and `pumpAndSettle` waits for a
            // still frame that never comes.
            animate: false,
          ),
        ),
      ),
      settle: false,
    );
    expect(tester.takeException(), isNull);

    final numeral = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.style?.color)
        .whereType<Color>()
        .toList();
    expect(numeral, isNotEmpty);
    for (final color in numeral) {
      expect(
        contrast(color, ground.base),
        greaterThan(1.35),
        reason: 'the countdown is invisible on the light ring',
      );
    }
  });

  testWidgets('Moments reads on paper', (tester) async {
    await pumpThenFlipToLight(tester, const MomentsTimelinePage());
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, ground: ground.base, screen: 'Moments');
  });
}
