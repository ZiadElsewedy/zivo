import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/date_format.dart';
import 'package:zivo/features/profile/presentation/widgets/dob_picker_sheet.dart';
import 'package:zivo/l10n/l10n.dart';

/// Arabic coverage for the profile surfaces. As elsewhere in this push, the
/// assertion that matters is the *absence* of English — a render test would
/// pass just as well on the hardcoded copy this replaces.
Future<T> _inApp<T>(
  WidgetTester tester,
  Locale locale,
  T Function(BuildContext) body,
) async {
  late T out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          out = body(context);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return out;
}

void main() {
  group('the date-of-birth picker', () {
    testWidgets('lists its months in Arabic, not from an English table', (tester) async {
      final months = await _inApp(tester, const Locale('ar'), monthNames);
      expect(months, hasLength(12));
      expect(months.first, 'يناير');
      expect(months.last, 'ديسمبر');
      for (final m in months) {
        expect(
          RegExp(r'[A-Za-z]').hasMatch(m),
          isFalse,
          reason: '"$m" is still an English month name',
        );
      }
    });

    testWidgets('still reads English under Locale("en")', (tester) async {
      final months = await _inApp(tester, const Locale('en'), monthNames);
      expect(months.first, 'January');
      expect(months[11], 'December');
    });

    testWidgets('the sheet renders its title and action in Arabic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DobPickerSheet()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Date of birth'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.text('تاريخ الميلاد'), findsOneWidget);
      expect(find.text('يناير'), findsWidgets);
    });
  });

  group('profile copy', () {
    testWidgets('the strings the pages read resolve in both languages', (tester) async {
      final ar = await _inApp(tester, const Locale('ar'), l);
      final en = await _inApp(tester, const Locale('en'), l);

      // Copy: must differ between locales.
      for (final pair in <(String, String)>[
        (ar.profileCompleteTitle, en.profileCompleteTitle),
        (ar.profileAbout, en.profileAbout),
        (ar.profileVerifiedCaps, en.profileVerifiedCaps),
        (ar.profileEmailAndPassword, en.profileEmailAndPassword),
        (ar.profileStatSessions, en.profileStatSessions),
      ]) {
        expect(pair.$1, isNot(pair.$2));
        expect(
          RegExp(r'[A-Za-z]').hasMatch(pair.$1),
          isFalse,
          reason: '"${pair.$1}" still contains latin text',
        );
      }

      // The one deliberate exception: the product name is never translated.
      expect(ar.profileCompleteSubtitle, contains('ZIVO'));
    });
  });
}
