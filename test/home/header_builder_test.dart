import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zivo/features/home/presentation/header_builder.dart';
import 'package:zivo/l10n/app_localizations_ar.dart';
import 'package:zivo/l10n/app_localizations_en.dart';

void main() {
  // The app gets these from `GlobalMaterialLocalizations`; a unit test has to
  // ask for them itself.
  setUpAll(initializeDateFormatting);

  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  group('formatTodayShort', () {
    test('formats as clipped, all-caps "DDD D MMM"', () {
      expect(formatTodayShort(DateTime(2026, 8, 15), 'en'), 'SAT 15 AUG');
    });

    test('formats a different weekday and month', () {
      expect(formatTodayShort(DateTime(2026, 1, 1), 'en'), 'THU 1 JAN');
    });

    test('day and month names come from intl, so Arabic needs no ARB keys', () {
      final arabic = formatTodayShort(DateTime(2026, 8, 15), 'ar');
      // Not asserting the exact abbreviation — that is intl's CLDR data and
      // not ZIVO's to pin. What matters is that it stopped being English.
      expect(arabic, isNot(contains('SAT')));
      expect(arabic, isNot(contains('AUG')));
      expect(arabic, contains('15'));
    });
  });

  group('greetingFor', () {
    test('morning bucket (before noon) with a name', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), 'Ziad', en), 'Morning, Ziad');
    });

    test('afternoon bucket (noon–5pm) with a name', () {
      expect(
        greetingFor(DateTime(2026, 1, 1, 14), 'Ziad', en),
        'Afternoon, Ziad',
      );
    });

    test('evening bucket (6pm and later) with a name', () {
      expect(greetingFor(DateTime(2026, 1, 1, 20), 'Ziad', en), 'Evening, Ziad');
    });

    test('boundary hours land in the right bucket', () {
      expect(
        greetingFor(DateTime(2026, 1, 1, 11, 59), 'Ziad', en),
        'Morning, Ziad',
      );
      expect(
        greetingFor(DateTime(2026, 1, 1, 12), 'Ziad', en),
        'Afternoon, Ziad',
      );
      expect(
        greetingFor(DateTime(2026, 1, 1, 17, 59), 'Ziad', en),
        'Afternoon, Ziad',
      );
      expect(greetingFor(DateTime(2026, 1, 1, 18), 'Ziad', en), 'Evening, Ziad');
    });

    test('falls back to a nameless greeting when name is null or blank', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), null, en), 'Good morning');
      expect(greetingFor(DateTime(2026, 1, 1, 8), '   ', en), 'Good morning');
    });

    test('uses only the first word of a multi-word name', () {
      expect(
        greetingFor(DateTime(2026, 1, 1, 8), 'Ziad Elsewedy', en),
        'Morning, Ziad',
      );
    });

    test('uses the whole name when it is a single word', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), 'Ziad', en), 'Morning, Ziad');
    });

    test('Arabic attaches the name with يا, not a comma — which is why the '
        'whole phrase is a key rather than a "{greeting}, {name}" template', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), 'Ziad', ar), 'صباح الخير يا Ziad');
      expect(greetingFor(DateTime(2026, 1, 1, 8), null, ar), 'صباح الخير');
      // Arabic has no distinct afternoon greeting; both buckets say مساء الخير.
      expect(greetingFor(DateTime(2026, 1, 1, 14), null, ar), 'مساء الخير');
      expect(greetingFor(DateTime(2026, 1, 1, 20), null, ar), 'مساء الخير');
    });
  });
}
