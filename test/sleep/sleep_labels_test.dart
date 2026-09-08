import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/domain/sleep_metrics.dart';
import 'package:zivo/features/sleep/presentation/sleep_labels.dart';
import 'package:zivo/l10n/l10n.dart';

/// Cover for the copy contract's **bidi** half, which a device caught and the
/// suite did not.
///
/// `sleepDurationText` was originally wrapped in `ltrFor`, on the assumption
/// that "7h 12m" is a composed numeric run. In Arabic it is not: the localized
/// form is `7س 12د`, and `س`/`د` are abbreviated words — strong right-to-left
/// characters. Forcing that run left-to-right interleaved the two number+unit
/// pairs and the hero rendered `س12د7`, which is not a duration in any
/// language. `core/util/bidi.dart` states the rule these tests now enforce: a
/// translated label is real text with a real direction and must be left alone.
Future<String> _render(
  WidgetTester tester,
  Locale locale,
  String Function(BuildContext) build,
) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          result = build(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

/// The Unicode directional isolates `ltrFor` inserts — written as escapes,
/// because the literal characters are invisible and reorder this file's own
/// source in an editor.
const _isolates = ['\u2066', '\u2068', '\u2069'];

void main() {
  const en = Locale('en');
  const ar = Locale('ar');

  group('durations carry no directional overrides', () {
    testWidgets('English is the plain string', (tester) async {
      final text = await _render(
        tester,
        en,
        (c) => sleepDurationText(c, const Duration(hours: 7, minutes: 12)),
      );
      expect(text, '7h 12m');
    });

    testWidgets('Arabic keeps its own direction, unpinned', (tester) async {
      final text = await _render(
        tester,
        ar,
        (c) => sleepDurationText(c, const Duration(hours: 7, minutes: 12)),
      );

      // The regression: an LTR isolate here reorders `7س 12د` into `س12د7`.
      for (final mark in _isolates) {
        expect(
          text.contains(mark),
          isFalse,
          reason: 'a translated duration must not be pinned left-to-right',
        );
      }
      expect(text, contains('7'));
      expect(text, contains('12'));
    });

    testWidgets('a sub-hour duration drops the hours entirely', (tester) async {
      expect(
        await _render(
          tester,
          en,
          (c) => sleepDurationText(c, const Duration(minutes: 48)),
        ),
        '48m',
      );
    });

    testWidgets('a whole number of hours drops the minutes', (tester) async {
      expect(
        await _render(
          tester,
          en,
          (c) => sleepDurationText(c, const Duration(hours: 8)),
        ),
        '8h',
      );
    });
  });

  group('composed figures stay unpinned in Arabic too', () {
    testWidgets('nights-of', (tester) async {
      final text = await _render(tester, ar, (c) => sleepNightsOfText(c, 5, 7));
      for (final mark in _isolates) {
        expect(text.contains(mark), isFalse);
      }
    });

    testWidgets('variability', (tester) async {
      final text = await _render(tester, ar, (c) => sleepVariabilityText(c, 44));
      for (final mark in _isolates) {
        expect(text.contains(mark), isFalse);
      }
      expect(text, contains('44'));
    });
  });

  group('the gates the UI renders', () {
    test('a comparison reports the weaker week, not the fuller one', () {
      // The bug this pins: a full current week against an empty previous one
      // rendered "not enough nights yet — 5 of 5", which reads as a fault.
      final current = SleepMetrics.forWindow(const [], windowNights: 7);
      expect(current.nightCount, 0);

      final comparison = SleepMetrics.compare(
        current: current,
        previous: current,
      );
      expect(comparison.verdict, SleepComparisonVerdict.insufficientData);
      expect(comparison.deltaMinutes, isNull);
    });
  });
}
