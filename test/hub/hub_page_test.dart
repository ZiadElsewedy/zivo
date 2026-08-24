import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';
import 'package:zivo/features/moments/presentation/pages/moments_timeline_page.dart';

import '../support/test_app.dart';

/// Regression coverage for the Hub grid clipping/overflowing on a short
/// device with the premium tile ratio — R2's fix drops
/// `NeverScrollableScrollPhysics` in favor of a genuinely scrollable grid,
/// so no device height or text scale can ever produce a layout overflow.
///
/// Each tile now reads live from `AppScope` (see `hub_page.dart`), so every
/// pump here needs a real scope — `wrapWithScope` gives fresh, seeded
/// in-memory repos (the same seed data `test/support/test_app.dart` uses
/// everywhere else).
void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: wrapWithScope(const HubPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a short device (iPhone SE-class) shows all modules with no overflow error',
    (tester) async {
      await pumpAt(
        tester,
        const Size(750, 1334),
      ); // iPhone SE logical size at 1x
      expect(tester.takeException(), isNull);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);
    },
  );

  testWidgets(
    'an even shorter viewport with large accessibility text scale still has no overflow',
    (tester) async {
      await pumpAt(tester, const Size(750, 900), textScale: 1.6);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the grid scrolls to reveal every module rather than clipping any of them',
    (tester) async {
      await pumpAt(tester, const Size(750, 900), textScale: 1.6);
      expect(tester.takeException(), isNull);

      // Scroll the grid to the bottom and confirm the last module is reachable
      // and rendered — proving it's a real scrollable, not a fixed grid that
      // silently clips whatever doesn't fit.
      await tester.drag(find.byType(GridView), const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Moments'), findsOneWidget);
    },
  );

  testWidgets(
    'a tall device has no overflow either (the premium ratio, not a squished fallback)',
    (tester) async {
      await pumpAt(tester, const Size(1170, 2532)); // iPhone-class tall device
      expect(tester.takeException(), isNull);
      expect(find.text('Workout'), findsOneWidget);
    },
  );

  testWidgets(
    'each tile shows a live stat from its own repo, and tapping one opens that module',
    (tester) async {
      await pumpAt(tester, const Size(1170, 2532));

      // Diet: the seeded plan has 3 meals, none eaten yet.
      expect(find.text('0 of 3 · 1270 kcal'), findsOneWidget);
      // Expenses: the seeded expenses sum to exactly 685 EGP within the trailing week.
      expect(find.text('EGP 685 this week'), findsOneWidget);
      // Moments: seeded with exactly one.
      expect(find.text('1 moment'), findsOneWidget);
      // Workout: seeded with a real active plan, so it never falls back to empty copy.
      expect(find.text('No plan yet'), findsNothing);

      // Tapping Moments (not Expenses — `ExpensesListPage` separately
      // requires `AppScope.wallet`, which is a wallet-feature concern
      // orthogonal to this Hub-tile test) opens that module.
      await tester.tap(find.text('Moments'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MomentsTimelinePage), findsOneWidget);
    },
  );

  testWidgets(
    'the Diet stat does not truncate at a standard phone width and default text scale',
    (tester) async {
      // A realistic phone logical width (iPhone 14/15-class) — the other
      // fixtures in this file use physical-pixel-as-logical sizes (750,
      // 1170), which are unrealistically wide for text-wrapping purposes and
      // is exactly why this didn't get caught earlier: "0 of 3 meals · 1270
      // kcal left" ellipsized to "1270 …" on an actual device at this width.
      await pumpAt(tester, const Size(390, 844));

      final finder = find.text('0 of 3 · 1270 kcal');
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).maxLines, 2);
      expect(
        (tester.renderObject(finder) as RenderParagraph).didExceedMaxLines,
        isFalse,
      );
    },
  );
}
