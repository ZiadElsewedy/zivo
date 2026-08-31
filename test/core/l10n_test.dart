import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/l10n/l10n.dart';

/// The l10n foundation's contract. These are cheap guards on the two ways a
/// two-language app silently degrades: a key that only exists in English, and
/// a screen that reads strings without a delegate above it.
void main() {
  Map<String, dynamic> arb(String name) =>
      jsonDecode(File('lib/l10n/$name').readAsStringSync())
          as Map<String, dynamic>;

  Set<String> keysOf(Map<String, dynamic> m) =>
      m.keys.where((k) => !k.startsWith('@')).toSet();

  test('every English key is translated into Arabic, and vice versa', () {
    final en = keysOf(arb('app_en.arb'));
    final ar = keysOf(arb('app_ar.arb'));

    // A key present in en but not ar renders as English inside an otherwise
    // Arabic screen — the failure mode that looks like a bug rather than a
    // missing translation, so it's worth failing the build over.
    expect(en.difference(ar), isEmpty, reason: 'untranslated in app_ar.arb');
    expect(ar.difference(en), isEmpty, reason: 'orphaned in app_ar.arb');
  });

  test('every English key carries a description for the translator', () {
    final en = arb('app_en.arb');
    final missing = keysOf(en)
        .where((k) => k != 'appTitle' && !en.containsKey('@$k'))
        .toList();
    expect(missing, isEmpty, reason: 'no @description in app_en.arb');
  });

  testWidgets('l(context) falls back to English with no delegates installed', (
    tester,
  ) async {
    // This is the widget-test case: a page pumped under a bare MaterialApp.
    // It must render, not throw.
    late String title;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            title = l(context).dietTitle;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(title, 'Diet');
  });

  testWidgets('the Arabic locale resolves Arabic strings and lays out RTL', (
    tester,
  ) async {
    late String title;
    late TextDirection direction;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            title = l(context).dietTitle;
            direction = Directionality.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(title, 'التغذية');
    // RTL is a consequence of the locale, not of anything a screen does — if
    // this ever fails, a screen has hardcoded a Directionality somewhere.
    expect(direction, TextDirection.rtl);
  });

  testWidgets('both languages supply a meal label and a calories-left figure', (
    tester,
  ) async {
    for (final (locale, meal, kcal) in const [
      (Locale('en'), 'Meal 3', '1240 kcal left'),
      (Locale('ar'), 'الوجبة 3', 'باقي 1240 سعرة'),
    ]) {
      late AppLocalizations s;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              s = l(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(s.dietMealNumber(3), meal);
      expect(s.dietKcalLeft(1240), kcal);
    }
  });
}
