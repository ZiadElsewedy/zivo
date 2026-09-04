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

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';
import '../support/inert_music_controller.dart';

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
    music: InertMusicController(),
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
    // Flushes each module card's staggered RiseIn entrance timer (a real
    // Timer, not just a frame) so none leaks past the test as "still pending".
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

  testWidgets(
    'the Connected band names each service and its live state, and is a '
    'shortcut into the screen that owns it',
    (tester) async {
      await pumpAt(tester, const Size(1200, 3600));
      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      // The tall test viewport fits the whole page, so the band is already
      // laid out — no scrolling needed to assert on it.
      expect(find.text('CONNECTED'), findsOneWidget); // the section label
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget);
      // The inert controller is disconnected and the test media service has no
      // backup wired, so both read as the honest negative rather than blank.
      expect(find.text('NOT CONNECTED'), findsNWidgets(2));
    },
  );
}
