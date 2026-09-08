import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/presentation/widgets/diet_glance.dart';
import 'package:zivo/l10n/l10n.dart';

import '../support/bidi_finders.dart';

Widget _host(
  Locale locale, {
  required bool againstTarget,
  int kcalLeft = 1400,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: DietGlanceRow(
      eaten: 2,
      total: 5,
      kcalLeft: kcalLeft,
      kcalEstimated: false,
      againstTarget: againstTarget,
    ),
  ),
);

void main() {
  group("Today's diet glance", () {
    // It was two English sentences built by interpolation — "2 of 5 meals
    // eaten" and "1400 kcal left of plan" — sitting on an otherwise fully
    // Arabic Today. The meals half even had an ARB key already; the widget
    // simply never read it.
    testWidgets('speaks Arabic', (tester) async {
      await tester.pumpWidget(_host(const Locale('ar'), againstTarget: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('meals eaten'), findsNothing);
      expect(find.textContaining('kcal left'), findsNothing);
      expect(find.textContaining('2 من 5'), findsOneWidget);
    });

    testWidgets('English is unchanged', (tester) async {
      await tester.pumpWidget(_host(const Locale('en'), againstTarget: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 of 5 meals eaten'), findsOneWidget);
      expect(find.textContaining('1400 kcal left of plan'), findsOneWidget);
    });

    testWidgets('the figure is pinned, so it survives an Arabic sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Locale('ar'), againstTarget: true, kcalLeft: -200),
      );
      await tester.pumpAndSettle();

      // Reads back as "200" with the directional isolate stripped: the run is
      // pinned in place, not reordered by the sentence around it.
      expect(findTextContainingIgnoringBidi('200'), findsWidgets);
    });
  });
}
