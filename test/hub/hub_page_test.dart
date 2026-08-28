import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_repository.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/features/moments/domain/moment_repository.dart';
import 'package:zivo/features/moments/presentation/pages/moments_timeline_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/presentation/pages/workout_dashboard_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

/// A fixed-list [ExpenseRepository] — the real `InMemoryExpenseRepository`
/// always self-seeds its own 5 demo expenses with no override, so this is
/// needed for deterministic control over the Recent section's merge.
class _FixedExpenseRepository implements ExpenseRepository {
  _FixedExpenseRepository(this._items);

  final List<Expense> _items;

  @override
  List<Expense> get current => _items;

  @override
  Stream<List<Expense>> watchAll() => Stream.value(_items);

  @override
  Future<void> add(Expense expense) async {}

  @override
  Future<void> update(Expense expense) async {}

  @override
  Future<void> remove(String id) async {}
}

/// A fixed-list [MomentRepository] — same reasoning as
/// [_FixedExpenseRepository] (the real one always self-seeds one demo
/// moment).
class _FixedMomentRepository implements MomentRepository {
  _FixedMomentRepository(this._items);

  final List<Moment> _items;

  @override
  List<Moment> get current => _items;

  @override
  Stream<List<Moment>> watchAll() => Stream.value(_items);

  @override
  Future<void> add(Moment moment) async {}

  @override
  Future<void> update(Moment moment) async {}

  @override
  Future<void> remove(String id) async {}
}

/// Like `wrapWithScope`, but with explicit control over expenses/moments/
/// workoutSessions — needed to test the Recent section's cross-module merge
/// deterministically rather than relying on the real repos' fixed seed data.
Widget _wrapWithData({
  List<Expense> expenses = const [],
  List<Moment> moments = const [],
  List<LiveSession> sessions = const [],
}) {
  return AppScope(
    media: testMediaService(),
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: _FixedExpenseRepository(expenses),
    moments: _FixedMomentRepository(moments),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(seed: sessions),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: const MaterialApp(home: HubPage()),
  );
}

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
    // Flushes the Recent section's RiseIn entrance timer (Future.delayed —
    // a real Timer, not just a frame) so it doesn't leak past the test as
    // "still pending" once one is present (i.e. any time a genuinely-empty
    // scope isn't in play).
    await tester.pump(const Duration(milliseconds: 400));
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
      expect(find.text('0 OF 3 · 1270 KCAL'), findsOneWidget);
      // Expenses: the seeded expenses sum to exactly 685 EGP within the trailing week.
      expect(find.text('EGP 685 THIS WEEK'), findsOneWidget);
      // Moments: seeded with exactly one.
      expect(find.text('1 MOMENT'), findsOneWidget);
      // Workout: seeded with a real active plan, so it never falls back to empty copy.
      expect(find.text('NO PLAN YET'), findsNothing);

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

      final finder = find.text('0 OF 3 · 1270 KCAL');
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).maxLines, 2);
      expect(
        (tester.renderObject(finder) as RenderParagraph).didExceedMaxLines,
        isFalse,
      );
    },
  );

  group('the Recent section', () {
    testWidgets(
      'merges modules newest-first and caps at 5, tapping a row opens that module',
      (tester) async {
        final now = DateTime.now();
        final day = const WorkoutDay(
          id: 'd1',
          slot: 'A',
          label: 'Push',
          order: 0,
          exercises: [],
        );
        final session = LiveSession.start(
          day,
          id: 's1',
          planId: 'p1',
          now: now.subtract(const Duration(hours: 3)),
        ).complete(now: now.subtract(const Duration(minutes: 1)));

        await tester.pumpWidget(
          _wrapWithData(
            sessions: [session],
            expenses: [
              Expense(
                id: 'e1',
                amountMinor: 4500,
                currency: 'EGP',
                categoryId: 'coffee',
                spentAt: now.subtract(const Duration(hours: 2)),
              ),
              Expense(
                id: 'e2',
                amountMinor: 1200,
                currency: 'EGP',
                categoryId: 'food',
                spentAt: now.subtract(const Duration(days: 1)),
              ),
              Expense(
                id: 'e3',
                amountMinor: 900,
                currency: 'EGP',
                categoryId: 'transport',
                spentAt: now.subtract(const Duration(days: 2)),
              ),
            ],
            moments: [
              Moment(
                id: 'm1',
                caption: 'Sunset walk',
                takenAt: now.subtract(const Duration(days: 3)),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('RECENT'), findsOneWidget);
        // 5 sources total (1 session + 3 expenses + 1 moment) — none dropped
        // here since the cap is 5.
        expect(find.text('Completed Push'), findsOneWidget);
        expect(find.text('45 EGP on Coffee'), findsOneWidget);
        expect(find.text('12 EGP on Food'), findsOneWidget);
        expect(find.text('9 EGP on Transport'), findsOneWidget);
        expect(find.text('Sunset walk'), findsOneWidget);

        // Newest (the session, completed 1 minute ago) renders first.
        final rowTexts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        final sessionIndex = rowTexts.indexOf('Completed Push');
        final oldestExpenseIndex = rowTexts.indexOf('9 EGP on Transport');
        expect(sessionIndex, greaterThanOrEqualTo(0));
        expect(sessionIndex, lessThan(oldestExpenseIndex));

        // The row is below the fold on the default test viewport — scroll
        // it into view before tapping, same as a real device would need a
        // real scroll first.
        await tester.ensureVisible(find.text('Completed Push'));
        await tester.tap(find.text('Completed Push'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(WorkoutDashboardPage), findsOneWidget);
      },
    );

    testWidgets('caps at 5 items even when more are available', (tester) async {
      final now = DateTime.now();
      final expenses = [
        for (var i = 0; i < 8; i++)
          Expense(
            id: 'e$i',
            amountMinor: 100,
            currency: 'EGP',
            categoryId: 'other',
            spentAt: now.subtract(Duration(hours: i)),
          ),
      ];

      await tester.pumpWidget(_wrapWithData(expenses: expenses));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1 EGP on Other'), findsNWidgets(5));
    });

    testWidgets(
      "a custom category's opaque id never leaks into the row — falls back to a generic label",
      (tester) async {
        await tester.pumpWidget(
          _wrapWithData(
            expenses: [
              Expense(
                id: 'e1',
                amountMinor: 500,
                currency: 'EGP',
                // A real custom category id is `microsecondsSinceEpoch`
                // (see add_category_sheet.dart) — opaque, not a slug.
                categoryId: '1735689600123456',
                spentAt: DateTime.now(),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('5 EGP on Expense'), findsOneWidget);
        expect(find.textContaining('1735689600123456'), findsNothing);
      },
    );

    testWidgets('renders nothing when every source is empty', (tester) async {
      await tester.pumpWidget(_wrapWithData());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('RECENT'), findsNothing);
    });
  });
}
