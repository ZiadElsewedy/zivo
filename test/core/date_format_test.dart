import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/date_format.dart';
import 'package:zivo/l10n/l10n.dart';

/// The point of `core/util/date_format.dart` is that a date renders in the
/// reader's language. Thirteen files used to index a hardcoded English
/// `['Jan', …]` table, which no `.arb` key could ever translate — so the
/// assertion that matters here is the **Arabic** one.
Future<String> _render(
  WidgetTester tester,
  Locale? locale,
  String Function(BuildContext) build,
) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          out = build(context);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return out;
}

void main() {
  final march1 = DateTime(2026, 3, 1, 6, 30, 45); // a Sunday

  group('English', () {
    testWidgets('month/day, weekday and clock read as before', (tester) async {
      expect(
        await _render(tester, const Locale('en'), (c) => formatMonthDay(c, march1)),
        'Mar 1',
      );
      expect(
        await _render(tester, const Locale('en'), (c) => formatMonthDayCaps(c, march1)),
        'MAR 1',
      );
      expect(
        await _render(tester, const Locale('en'), (c) => formatWeekdayShort(c, march1)),
        'Sun',
      );
      expect(
        await _render(tester, const Locale('en'), (c) => formatClockTime(c, march1)),
        '6:30 AM',
      );
    });

    testWidgets('minutes since midnight round-trip to a clock time', (tester) async {
      expect(
        await _render(tester, const Locale('en'), (c) => formatMinutesSinceMidnight(c, 6 * 60 + 30)),
        '6:30 AM',
      );
      expect(
        await _render(tester, const Locale('en'), (c) => formatMinutesSinceMidnight(c, 18 * 60 + 5)),
        '6:05 PM',
      );
    });
  });

  group('Arabic — what the hardcoded English tables could never do', () {
    testWidgets('the month name is Arabic, not "Mar"', (tester) async {
      final out = await _render(tester, const Locale('ar'), (c) => formatMonthDay(c, march1));
      expect(out, isNot(contains('Mar')));
      expect(out, contains('مارس'));
    });

    testWidgets('the weekday is Arabic, not "Sun"', (tester) async {
      final out = await _render(tester, const Locale('ar'), (c) => formatWeekdayShort(c, march1));
      expect(out, isNot(contains('Sun')));
      expect(out, contains('أحد'));
    });

    testWidgets('the day period is Arabic, not "AM"', (tester) async {
      final out = await _render(tester, const Locale('ar'), (c) => formatClockTime(c, march1));
      expect(out, isNot(contains('AM')));
      expect(out, contains('ص'));
    });

    testWidgets('caps is a no-op in a script that has no case', (tester) async {
      final plain = await _render(tester, const Locale('ar'), (c) => formatMonthDay(c, march1));
      final caps = await _render(tester, const Locale('ar'), (c) => formatMonthDayCaps(c, march1));
      expect(caps, plain);
    });
  });

  group('no Localizations at all (the bare-MaterialApp widget test case)', () {
    testWidgets('falls back to English instead of throwing', (tester) async {
      late String out;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              out = formatMonthDay(context, march1);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(out, 'Mar 1');
    });
  });
}
