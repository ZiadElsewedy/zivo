import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/features/shell/presentation/widgets/zivo_bottom_bar.dart';
import 'package:zivo/l10n/l10n.dart';

/// The ember capsule must sit under the tab that is actually selected — in
/// Arabic as well as English.
///
/// The bar draws its tabs in a [Row] (which reverses under RTL) and its
/// capsule in a [Stack] positioned by offset. Those two only agree if the
/// offset is measured from the *leading* edge; measured from the geometric
/// left, the capsule mirrored — in Arabic it lit the tab opposite the one the
/// user tapped, which is the single most visible thing wrong with the bar in
/// RTL and is invisible to every English test.
Future<void> _pumpBar(WidgetTester tester, Locale locale, int index) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: ZivoBottomBar(
          currentIndex: index,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The capsule is the one ember-wash filled box in the bar.
final Finder _capsule = find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).color == TrainColors.emberWash,
);

const _tabIcons = [
  AppIcons.today,
  AppIcons.hub,
  AppIcons.ask,
  AppIcons.you,
];

void main() {
  for (final locale in const [Locale('en'), Locale('ar')]) {
    for (var index = 0; index < _tabIcons.length; index++) {
      testWidgets(
        'capsule sits under tab $index in ${locale.languageCode}',
        (tester) async {
          await _pumpBar(tester, locale, index);

          expect(_capsule, findsOneWidget);
          final capsuleX = tester.getCenter(_capsule).dx;
          final tabX = tester.getCenter(find.byIcon(_tabIcons[index])).dx;

          expect(
            capsuleX,
            moreOrLessEquals(tabX, epsilon: 1.0),
            reason:
                'capsule at $capsuleX but tab $index is at $tabX '
                'in ${locale.languageCode}',
          );
        },
      );
    }
  }

  // The owner's call: the four destinations keep ONE physical order in every
  // language — Today at the left, You at the right — so a thumb that has
  // learned where a tab lives does not have to relearn it when the language
  // changes. This is a deliberate exception to platform mirroring; the test
  // exists so the exception is a decision on the record rather than something
  // a later RTL sweep "fixes" by accident.
  testWidgets('tab order is the same physical order in every language', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      await _pumpBar(tester, locale, 0);
      final xs = [
        for (final icon in _tabIcons) tester.getCenter(find.byIcon(icon)).dx,
      ];
      expect(
        xs,
        orderedEquals(<Object>[...xs]..sort()),
        reason:
            'Today → Hub → Ask → You must run left to right in '
            '${locale.languageCode}, but sat at $xs',
      );
    }
  });

  testWidgets('Arabic labels still render in the bar', (tester) async {
    await _pumpBar(tester, const Locale('ar'), 0);
    // Pinning the strip's geometry must not pin its *text*: each label is
    // still Arabic and still shapes right-to-left inside its own slot.
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
  });
}
