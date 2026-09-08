import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';
import 'package:zivo/features/moments/presentation/pages/moments_timeline_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_progress_page.dart';

import '../support/test_app.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Unicode private-use areas — where an icon font puts its glyphs.
bool _isGlyph(int rune) =>
    (rune >= 0xE000 && rune <= 0xF8FF) ||
    (rune >= 0xF0000 && rune <= 0x10FFFD);

double _contrast(Color ink, Color over) {
  final a = ink.a;
  final flat = Color.from(
    alpha: 1,
    red: ink.r * a + over.r * (1 - a),
    green: ink.g * a + over.g * (1 - a),
    blue: ink.b * a + over.b * (1 - a),
  );
  final l1 = _luminance(flat), l2 = _luminance(over);
  final (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1);
  return (hi + 0.05) / (lo + 0.05);
}

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

  /// Every rendered run of text, with the style the framework actually
  /// resolved — `RichText` rather than `Text`, so inherited defaults and
  /// `DefaultTextStyle` are already folded in.
  Iterable<(String, Color)> inks(WidgetTester tester) sync* {
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      final span = rich.text;
      final color = span.style?.color;
      final label = span.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      );
      if (color == null || color.a == 0) continue;
      // An `Icon` is a `RichText` too, carrying one private-use codepoint
      // from the glyph font. Icons on a filled pill or a photo scrim are
      // legitimately white in both skins, so only real text is measured.
      final text = label.trim();
      if (text.isEmpty || text.runes.every(_isGlyph)) continue;
      yield (text, color);
    }
  }

  void expectNothingVanishes(WidgetTester tester, String screen) {
    var checked = 0;
    for (final (label, color) in inks(tester)) {
      checked++;
      expect(
        _contrast(color, ground.base),
        greaterThan(1.35),
        reason: '$screen: "$label" is invisible on the light ground '
            '(${color.toARGB32().toRadixString(16)})',
      );
    }
    // A screen that rendered no text at all would pass the loop vacuously.
    expect(checked, greaterThan(3), reason: '$screen rendered almost no text');
  }

  testWidgets('the Hub reads on paper', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(const HubPage(), brightness: Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, 'Hub');
  });

  testWidgets('Settings reads on paper', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(const SettingsPage(), brightness: Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, 'Settings');
  });

  testWidgets('a chart screen reads on paper', (tester) async {
    // Charts are where a skin usually breaks first: axis labels and grid
    // rules are the quietest ink on any screen.
    await tester.pumpWidget(
      wrapWithScope(const WorkoutProgressPage(), brightness: Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, 'Workout progress');
  });

  testWidgets('Moments reads on paper', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(const MomentsTimelinePage(), brightness: Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNothingVanishes(tester, 'Moments');
  });
}
