import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/core/theme/theme_controller.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/core/theme/zivo_palette.dart';

/// WCAG relative luminance, then the contrast ratio between two opaque
/// colours. The light skin's whole job is to hold these numbers, so the
/// numbers are the test.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// [over] must be opaque; [ink] is composited onto it first, so an alpha step
/// like `ink3` is measured as it actually renders rather than at full strength.
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

void main() {
  // `ZivoTheme.use` reaches for the widget binding to schedule the repaint a
  // skin change implies, so even these value-level tests need one.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the dark skin is the one that shipped', () {
    // ADR-011 moved these values out of `TrainColors` and into a palette
    // instance. If that move changed any of them, it changed the look of an
    // app that was not supposed to change — so a sample of the load-bearing
    // ones is pinned here.
    test('its load-bearing values are byte-identical', () {
      const p = ZivoPalette.dark;
      expect(p.base, const Color(0xFF080908));
      expect(p.green, const Color(0xFF1FE08A));
      expect(p.ember, const Color(0xFFFF5C1A));
      expect(p.amber, const Color(0xFFE6BE3C));
      expect(p.violet, const Color(0xFF8F8BFF));
      expect(p.ink, const Color(0xFFF7F7F3));
      expect(p.ink2, const Color(0x73F4F4F0));
      expect(p.ink3, const Color(0x66F4F4F0));
      expect(p.ink4, const Color(0x52F4F4F0));
      expect(p.hairline, const Color(0x12FFFFFF));
      expect(p.raised, const Color(0xF0141514));
      expect(p.sleepAccent, const Color(0xFF7C9CFF));
    });

    test('it is what the app runs on until something swaps it', () {
      expect(ZivoTheme.palette, same(ZivoPalette.dark));
      expect(TrainColors.base, ZivoPalette.dark.base);
    });
  });

  group('the light skin is legible on paper', () {
    const p = ZivoPalette.light;

    test('the ground is off-white, not white', () {
      // A true #FFFFFF under near-black type reads as a document rather than
      // a product; the base carries the same faint cast the dark one does.
      expect(p.base, isNot(const Color(0xFFFFFFFF)));
      expect(_luminance(p.base), greaterThan(0.85));
    });

    test('primary and secondary ink clear AA on the base', () {
      expect(_contrast(p.ink, p.base), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.inkPlain, p.base), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.ink2, p.base), greaterThanOrEqualTo(4.5));
    });

    test('tertiary ink clears AA-large, which is what it is for', () {
      // ink3 and ink4 dress captions and disabled marks, never body copy.
      expect(_contrast(p.ink3, p.base), greaterThanOrEqualTo(3.0));
      expect(_contrast(p.ink4, p.base), greaterThanOrEqualTo(2.0));
    });

    test('every hue holds its own against the ground', () {
      // These carry glyphs, values and chip text, so 3:1 is the floor —
      // the dark skin's mint green sits at ~1.7:1 here, which is why the
      // light skin cannot simply reuse it.
      for (final (name, hue) in [
        ('green', p.green),
        ('ember', p.ember),
        ('amber', p.amber),
        ('violet', p.violet),
        ('sleepAccent', p.sleepAccent),
      ]) {
        expect(
          _contrast(hue, p.base),
          greaterThanOrEqualTo(3.0),
          reason: '$name is not legible on the light base',
        );
      }
    });

    test('a label on a filled hue is legible on that fill', () {
      // Each of these hues is a fill as often as it is a glyph, and this is
      // usually the binding constraint on how deep it has to go — deeper
      // than reading it against the page alone would ask for.
      for (final (name, ink, fill) in [
        ('onGreen', p.onGreen, p.green),
        ('onAmber', p.onAmber, p.amber),
        ('sleepOnAccent', p.sleepOnAccent, p.sleepAccent),
      ]) {
        expect(
          _contrast(ink, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name is not legible on the fill it labels',
        );
      }
    });

    test('the primary pill carries white at AA', () {
      // `TrainPrimaryButton` labels itself `Colors.white` on ember — the one
      // committing action on a screen, and the control least able to afford
      // being hard to read. Its lit gradient end has to hold up too.
      const white = Color(0xFFFFFFFF);
      expect(_contrast(white, p.ember), greaterThanOrEqualTo(4.5));
      expect(_contrast(white, p.emberLift), greaterThanOrEqualTo(3.5));
    });

    test('elevation still reads: raised sits above the page', () {
      expect(p.raised, isNot(p.base));
      expect(_luminance(p.raised), greaterThan(_luminance(p.base)));
      // ...and the step above `raised` has to go the other way, because
      // there is nothing lighter than white to go to.
      expect(_luminance(p.raisedStrong), lessThan(_luminance(p.raised)));
    });

    test('an arbitrary ink step lands where the named ones did', () {
      // `inkAt`/`liftAt` have to make the same journey the named steps made,
      // or ~100 call sites get a dark-tuned alpha on paper. The curve is
      // checked against the pairs it was derived from.
      for (final (onDark, onLight) in [
        (0.45, ZivoPalette.dark.ink2.a),
        (0.40, ZivoPalette.dark.ink3.a),
        (0.32, ZivoPalette.dark.ink4.a),
      ]) {
        expect(onDark, closeTo(onLight, 0.01)); // the dark pair, sanity
      }
      expect(p.inkAt(0.45).a, closeTo(p.ink2.a, 0.02));
      expect(p.inkAt(0.40).a, closeTo(p.ink3.a, 0.02));
      expect(p.inkAt(0.32).a, closeTo(p.ink4.a, 0.03));
      expect(p.liftAt(0.07).a, closeTo(p.hairline.a, 0.02));
      expect(p.liftAt(0.12).a, closeTo(p.hairlineStrong.a, 0.02));

      // ...and it saturates rather than clipping, which a plain multiplier
      // would do at the top of the range.
      expect(p.inkAt(0.8).a, lessThan(1.0));
      expect(p.inkAt(1.0).a, closeTo(1.0, 0.001));

      // The dark skin is the identity — its literals are the reference.
      expect(ZivoPalette.dark.inkAt(0.3).a, closeTo(0.3, 0.005));
    });

    test('a quiet caption stays as quiet-but-readable as it is on dark', () {
      // The live session's "of 5:00 planned" line, which is what surfaced
      // this: at a raw 0.3 it landed at 2.0:1 on paper against 3.2:1 on
      // near-black — the same token reading as two different decisions.
      final onLight = _contrast(p.inkAt(0.3), p.base);
      final onDark = _contrast(
        ZivoPalette.dark.inkAt(0.3),
        ZivoPalette.dark.base,
      );
      expect(onLight, greaterThan(2.6));
      expect((onLight - onDark).abs(), lessThan(1.0));
    });

    test('surface lifts are ink here and light on the dark skin', () {
      expect(ZivoPalette.dark.lift, const Color(0xFFFFFFFF));
      expect(_luminance(p.lift), lessThan(0.1));
    });
  });

  group('the two skins are actually two', () {
    test('every ground, ink and surface token differs between them', () {
      const d = ZivoPalette.dark, l = ZivoPalette.light;
      for (final (name, a, b) in [
        ('base', d.base, l.base),
        ('ink', d.ink, l.ink),
        ('ink2', d.ink2, l.ink2),
        ('hairline', d.hairline, l.hairline),
        ('raised', d.raised, l.raised),
        ('green', d.green, l.green),
        ('ember', d.ember, l.ember),
        ('amber', d.amber, l.amber),
        ('violet', d.violet, l.violet),
        ('lift', d.lift, l.lift),
      ]) {
        expect(a, isNot(b), reason: '$name did not flip');
      }
    });

    test('the session slab and its ink deliberately do not flip', () {
      // The Today card keeps its deep green in both skins — "one hero per
      // screen" is how a saturated slab earns its place on paper too.
      expect(ZivoPalette.dark.sessionInk, ZivoPalette.light.sessionInk);
      expect(
        ZivoPalette.dark.sessionInkMuted,
        ZivoPalette.light.sessionInkMuted,
      );
    });
  });

  group('ZivoTheme', () {
    setUp(ZivoTheme.resetForTesting);
    tearDown(ZivoTheme.resetForTesting);

    test('swapping the skin swaps what every token reads back', () {
      ZivoTheme.use(Brightness.light);
      expect(ZivoTheme.brightness, Brightness.light);
      expect(TrainColors.base, ZivoPalette.light.base);
      expect(TrainColors.ink, ZivoPalette.light.ink);
      expect(TrainColors.hubTint, ZivoPalette.light.hubTint);
      // The two aliases resolve through the active palette as well.
      expect(TrainColors.dietTint, ZivoPalette.light.hubTint);
      expect(TrainColors.macroProtein, ZivoPalette.light.green);

      ZivoTheme.use(Brightness.dark);
      expect(TrainColors.base, ZivoPalette.dark.base);
    });

    test('the action glow burns softer on paper than on near-black', () {
      ZivoTheme.use(Brightness.dark);
      final onDark = TrainColors.actionGlow(TrainColors.ember).single.color.a;
      ZivoTheme.use(Brightness.light);
      final onLight = TrainColors.actionGlow(TrainColors.ember).single.color.a;
      expect(onLight, lessThan(onDark));
    });
  });

  group('ThemeController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts dark, so shipping this does not re-skin anyone', () {
      expect(ThemeController.defaultMode, ThemeMode.dark);
      final c = ThemeController();
      addTearDown(c.dispose);
      expect(c.mode.value, ThemeMode.dark);
    });

    test('remembers the choice across a restart', () async {
      final first = ThemeController();
      await first.set(ThemeMode.light);
      first.dispose();

      final second = ThemeController();
      addTearDown(second.dispose);
      await second.load();
      expect(second.mode.value, ThemeMode.light);
    });

    test('stores the mode by name, as an id with no copy in it', () async {
      final c = ThemeController();
      addTearDown(c.dispose);
      await c.set(ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('zivo.themeMode'), 'system');
    });

    test('an unreadable or unknown stored value falls back rather than '
        'throwing', () async {
      SharedPreferences.setMockInitialValues({'zivo.themeMode': 'sepia'});
      final c = ThemeController(initial: ThemeMode.light);
      addTearDown(c.dispose);
      await c.load();
      expect(c.mode.value, ThemeController.defaultMode);
    });
  });
}
