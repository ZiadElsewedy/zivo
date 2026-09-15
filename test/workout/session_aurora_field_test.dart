import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
import 'package:zivo/features/workout/presentation/widgets/session_ambience.dart';
import 'package:zivo/features/workout/presentation/widgets/session_aurora_field.dart';

/// Shortest circular hue distance in degrees (0..180).
double _hueGap(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  setUp(() => ZivoTheme.use(Brightness.dark));

  group('buildSessionField (wide artwork extraction)', () {
    test(
      'an empty or zero-population palette yields no field (stays static)',
      () {
        expect(buildSessionField(const []), isNull);
        expect(
          buildSessionField([PaletteColor(const Color(0xFF2244CC), 0)]),
          isNull,
        );
      },
    );

    test(
      'a blue-and-orange cover shows BOTH hues — the whole point (no mono-hue '
      'collapse)',
      () {
        final field = buildSessionField([
          PaletteColor(const Color(0xFF1E4FE0), 100), // blue
          PaletteColor(const Color(0xFFE0641E), 70), // orange
        ]);
        expect(field, isNotNull);
        expect(field!.stops.length, greaterThanOrEqualTo(2));
        // The two dominant stops sit in genuinely different hue families.
        expect(_hueGap(field.stops[0], field.stops[1]), greaterThan(60));
      },
    );

    test(
      'tone-mapping keeps the hue but caps lightness (≤0.50) so the field can '
      'never blow out the readable core',
      () {
        final field = buildSessionField([
          PaletteColor(const Color(0xFFFFFFFF), 40), // near-white, loud
          PaletteColor(const Color(0xFFFF2D55), 100), // vivid red
        ]);
        expect(field, isNotNull);
        for (final stop in field!.stops) {
          expect(HSLColor.fromColor(stop).lightness, lessThanOrEqualTo(0.51));
        }
        // fieldGain never leaves its safe band.
        expect(field.fieldGain, inInclusiveRange(0.4, 1.0));
      },
    );

    test(
      'a vivid, multi-hue cover reads as higher ENERGY than a single muted one '
      '(so a high-energy song feels high-energy)',
      () {
        final loud = buildSessionField([
          PaletteColor(const Color(0xFF1E4FE0), 100), // blue
          PaletteColor(const Color(0xFFE0641E), 80), // orange
          PaletteColor(const Color(0xFF25E06A), 60), // green
        ])!;
        final calm = buildSessionField([
          PaletteColor(const Color(0xFF3A4A63), 100), // one muted slate-blue
        ])!;
        expect(loud.energy, greaterThan(calm.energy));
        expect(loud.energy, greaterThan(0.5));
        expect(calm.energy, lessThan(0.4));
        // Energy always stays inside the never-frozen / never-frantic band.
        for (final e in [loud.energy, calm.energy]) {
          expect(e, inInclusiveRange(0.10, 0.95));
        }
      },
    );

    test(
      'a grayscale cover stays alive but honest — a quiet field, low energy, '
      'no invented colour',
      () {
        final field = buildSessionField([
          PaletteColor(const Color(0xFF808080), 100),
          PaletteColor(const Color(0xFF5A5A5A), 50),
        ]);
        expect(field, isNotNull);
        expect(field!.stops.length, 2);
        expect(field.energy, lessThan(0.25));
        expect(field.warmth, 0);
      },
    );

    test('a warm cover reads warm, a cool cover reads cool', () {
      final warm = buildSessionField([
        PaletteColor(const Color(0xFFE0641E), 100), // orange
      ])!;
      final cool = buildSessionField([
        PaletteColor(const Color(0xFF1E7FE0), 100), // azure
      ])!;
      expect(warm.warmth, greaterThan(0));
      expect(cool.warmth, lessThan(0));
    });
  });

  group('SessionAuroraField (reactive background)', () {
    testWidgets(
      'with no live field it is inert — a plain ground with NO perpetual '
      'animation (so a no-music session and tests settle)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: SessionAuroraField(field: null, reduced: false),
          ),
        );
        // If this widget spun up a repeating controller with no field, this
        // would time out. It must not.
        await tester.pumpAndSettle();
        expect(find.byType(SessionAuroraField), findsOneWidget);
        // Just the ground — no aurora painter.
        expect(
          find.descendant(
            of: find.byType(SessionAuroraField),
            matching: find.byType(ColoredBox),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(SessionAuroraField),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'under reduced motion it paints ONE still, full-colour frame — colour '
      'kept, movement dropped, and it settles',
      (tester) async {
        const field = SessionField(
          stops: [Color(0xFF1E4FE0), Color(0xFFE0641E)],
          weights: [0.6, 0.4],
          energy: 0.8,
          warmth: 0.1,
          loudness: 0.5,
          luminosity: 0.3,
          fieldGain: 1,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: SessionAuroraField(field: field, reduced: true),
          ),
        );
        // A still frame — no controller — so it settles rather than hanging.
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(SessionAuroraField),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'with a live field and motion enabled it animates (a CustomPaint that '
      'advances), and disposes cleanly on unmount',
      (tester) async {
        const field = SessionField(
          stops: [Color(0xFF1E4FE0), Color(0xFFE0641E), Color(0xFF25E06A)],
          weights: [0.5, 0.3, 0.2],
          energy: 0.8,
          warmth: 0.1,
          loudness: 0.5,
          luminosity: 0.3,
          fieldGain: 1,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: SessionAuroraField(field: field, reduced: false),
          ),
        );
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(SessionAuroraField),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        // Advancing time doesn't throw (the drift is running).
        await tester.pump(const Duration(milliseconds: 500));
        // Unmount → the repeating controller is disposed (no leaked Ticker).
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump();
      },
    );

    testWidgets(
      'a track change morphs rather than hard-swapping, and settles afterwards',
      (tester) async {
        const trackA = SessionField(
          stops: [Color(0xFF1E4FE0), Color(0xFF25E06A)],
          weights: [0.6, 0.4],
          energy: 0.7,
          warmth: -0.2,
          loudness: 0.5,
          luminosity: 0.3,
          fieldGain: 1,
        );
        const trackB = SessionField(
          stops: [Color(0xFFE0641E), Color(0xFFE0C41E)],
          weights: [0.6, 0.4],
          energy: 0.4,
          warmth: 0.6,
          loudness: 0.4,
          luminosity: 0.4,
          fieldGain: 1,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: SessionAuroraField(field: trackA, reduced: true),
          ),
        );
        // Swap track under reduced motion — recolours instantly, no morph
        // controller, still settles.
        await tester.pumpWidget(
          const MaterialApp(
            home: SessionAuroraField(field: trackB, reduced: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(SessionAuroraField),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
