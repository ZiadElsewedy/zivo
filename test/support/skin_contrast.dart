import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/widgets/train_chrome.dart';
import 'package:zivo/core/widgets/train_surfaces.dart';
import 'package:zivo/features/auth/presentation/widgets/auth_action_button.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';

/// WCAG relative luminance.
double luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Contrast between [ink] and the opaque [over] it sits on. [ink] is
/// composited first, so an alpha step is measured as it actually renders
/// rather than at full strength.
double contrast(Color ink, Color over) {
  final a = ink.a;
  final flat = Color.from(
    alpha: 1,
    red: ink.r * a + over.r * (1 - a),
    green: ink.g * a + over.g * (1 - a),
    blue: ink.b * a + over.b * (1 - a),
  );
  final l1 = luminance(flat), l2 = luminance(over);
  final (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1);
  return (hi + 0.05) / (lo + 0.05);
}

/// Unicode private-use areas — where an icon font puts its glyphs. An `Icon`
/// is a `RichText` too, and icons on a filled pill are legitimately white in
/// either skin.
bool _isGlyph(int rune) =>
    (rune >= 0xE000 && rune <= 0xF8FF) ||
    (rune >= 0xF0000 && rune <= 0x10FFFD);

/// Widgets that paint a saturated hue behind their own label, so the text
/// inside them is measured against that fill and not against the page.
bool _isFilled(Widget w) =>
    w is TrainPrimaryButton ||
    w is TrainFab ||
    w is PillButton ||
    w is AuthActionButton;

/// **Asserts nothing on screen has all but vanished into [ground].**
///
/// The failure mode a second skin actually has is not "ugly", it is
/// *invisible*: one colour that stayed a literal, or a `static` that cached
/// the first skin the app drew, and a line of type is now the same value as
/// the page under it. So this reads the ink the framework actually resolved
/// off every run of text — `RichText`, so inherited defaults are folded in —
/// and holds it to a floor near the bottom of the range. Policing the
/// contrast *ladder* is `zivo_palette_test.dart`'s job, against the tokens;
/// this is only looking for text that is gone.
///
/// Text inside a filled pill is skipped: it sits on ember, not on the page,
/// and `zivo_palette_test` holds white-on-ember to 4.5:1 separately.
void expectNothingVanishes(
  WidgetTester tester, {
  required Color ground,
  required String screen,
  int minimumRuns = 5,
}) {
  final onFill = <Widget>{};
  void walk(Element element, bool filled) {
    final widget = element.widget;
    final inFill = filled || _isFilled(widget);
    if (inFill && widget is RichText) onFill.add(widget);
    element.visitChildren((child) => walk(child, inFill));
  }

  WidgetsBinding.instance.rootElement?.visitChildren((e) => walk(e, false));

  var checked = 0;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final color = rich.text.style?.color;
    if (color == null || color.a == 0 || onFill.contains(rich)) continue;
    final label = rich.text
        .toPlainText(includeSemanticsLabels: false, includePlaceholders: false)
        .trim();
    if (label.isEmpty || label.runes.every(_isGlyph)) continue;
    checked++;
    expect(
      contrast(color, ground),
      greaterThan(1.35),
      reason:
          '$screen: "$label" is invisible on the ground '
          '(${color.toARGB32().toRadixString(16)})',
    );
  }
  expect(
    checked,
    greaterThan(minimumRuns),
    reason: '$screen rendered almost no text — the check was vacuous',
  );
}
