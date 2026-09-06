import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/bidi.dart';
import 'package:zivo/features/auth/presentation/pages/privacy_page.dart';
import 'package:zivo/l10n/l10n.dart';

/// The privacy policy is a legal document, and the two things that would make
/// it a *wrong* one are both cheap to check: a section silently missing in one
/// language, and a section that renders as English inside the Arabic page.
///
/// It is also the one screen where an untranslated string is worse than
/// untidy — a reader who cannot read the English half has been shown a policy
/// they cannot consent to.
Future<List<PrivacySection>> _sectionsIn(
  WidgetTester tester,
  Locale locale,
) async {
  late List<PrivacySection> sections;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          sections = privacySections(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return sections;
}

/// True when [text] contains at least one Arabic letter.
bool _hasArabic(String text) =>
    RegExp(r'[؀-ۿ]').hasMatch(text);

/// True when [text] contains a run of latin letters that is not one of the
/// proper nouns the policy deliberately keeps in latin.
bool _hasStrayLatin(String text) {
  const allowed = {
    'ZIVO', 'Firebase', 'Authentication', 'Firestore', 'Google', 'Drive',
    'Spotify', 'Apple', 'SDK', 'drive', 'file', 'AI',
  };
  final words = RegExp(r'[A-Za-z]+').allMatches(text).map((m) => m.group(0)!);
  return words.any((w) => !allowed.contains(w));
}

void main() {
  testWidgets('every section exists in both languages, in the same order', (
    tester,
  ) async {
    final en = await _sectionsIn(tester, const Locale('en'));
    final ar = await _sectionsIn(tester, const Locale('ar'));

    expect(en, hasLength(15));
    expect(ar, hasLength(en.length));
    for (var i = 0; i < en.length; i++) {
      expect(
        ar[i].bullets.length,
        en[i].bullets.length,
        reason: 'section $i lost or gained a bullet in translation',
      );
      expect(
        ar[i].body.isEmpty,
        en[i].body.isEmpty,
        reason: 'section $i has a body in one language but not the other',
      );
    }
  });

  testWidgets('no section is left in English on the Arabic page', (
    tester,
  ) async {
    final ar = await _sectionsIn(tester, const Locale('ar'));

    for (final (i, section) in ar.indexed) {
      // SPOTIFY is a brand name and is the one label that stays latin.
      if (section.label != 'SPOTIFY') {
        expect(
          _hasArabic(section.label),
          isTrue,
          reason: 'section $i label is not translated: "${section.label}"',
        );
      }
      if (section.body.isNotEmpty) {
        expect(
          _hasArabic(section.body),
          isTrue,
          reason: 'section $i body is not translated',
        );
        expect(
          _hasStrayLatin(stripBidi(section.body).replaceAll(
            RegExp(r'[\w.@]+@[\w.]+'),
            '',
          )),
          isFalse,
          reason: 'section $i body still carries untranslated English',
        );
      }
      for (final bullet in section.bullets) {
        expect(_hasArabic(bullet), isTrue, reason: 'a bullet is untranslated');
      }
    }
  });

  testWidgets('the contact address is isolated, not translated', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final sections = await _sectionsIn(tester, locale);
      final contact = sections.last;
      expect(stripBidi(contact.body), contains(kPrivacyContactEmail));
      expect(
        contact.body,
        isNot(stripBidi(contact.body)),
        reason: 'the address must be wrapped in a directional isolate so an '
            'RTL paragraph cannot break it apart around the @',
      );
    }
  });
}
