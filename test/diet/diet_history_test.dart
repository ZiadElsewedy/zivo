import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/firestore_diet_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_day_record.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/presentation/pages/diet_history_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/diet/presentation/pages/meal_detail_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/l10n/app_localizations.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// `test/fixtures/diet_day_record_vectors.json` is written by the server's
/// `functions/diet/day_record.js` and rebuilt by `day_record.test.js`; this
/// side proves the app reads exactly that shape.
Map<String, dynamic> _vector() =>
    jsonDecode(
          File('test/fixtures/diet_day_record_vectors.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

DietPlan _plan() => DietPlan(
  id: 'p',
  name: 'Cut',
  status: DietPlanStatus.active,
  source: DietSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  days: const [
    DietDay(
      weekday: null,
      label: 'Every day',
      meals: [
        Meal(
          id: 'meal-1',
          label: 'Lunch',
          order: 0,
          items: [
            FoodItem(name: 'Rice', quantity: 150, unit: 'g', calories: 210),
            FoodItem(
              name: 'Chicken',
              quantity: 200,
              unit: 'g',
              calories: 330,
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _wrap(Widget child, InMemoryDietRepository diet) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: diet,
  ai: FakeAiRepository(),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  group('DietDayRecord', () {
    test('parses the record the server builds (shared vector)', () {
      final record = DietDayRecord.fromMap(
        Map<String, dynamic>.from(_vector()['record'] as Map),
      )!;
      expect(record.dayKey, '2026-09-25');
      expect(record.planName, 'Cut');
      expect(record.planReconstructed, isTrue);
      expect(record.target!.calories, 2000);
      expect(record.meals.map((m) => m.status).toList(), [
        MealTrackingStatus.eaten,
        MealTrackingStatus.modified,
        MealTrackingStatus.skipped,
        MealTrackingStatus.unmarked,
        MealTrackingStatus.unmarked,
      ]);
      // Supplements are tracked but never counted as meals.
      expect(record.meals.last.isSupplement, isTrue);
      expect(record.mealsPlanned, 4);
      expect(record.mealsConsumed, 2);
      expect(record.count(MealTrackingStatus.skipped), 1);
      expect(record.meals[1].planned!.kcal, 330);
      expect(record.meals[1].actual!.kcal, 248);
      expect(record.consumed.kcal, 671);
      expect(record.consumed.basis, 'logged');
      expect(record.unplannedCount, 1);
      expect(record.unplanned.kcal, 95);
    });

    test('a malformed document is dropped, never rendered as zeros', () {
      expect(DietDayRecord.fromMap({'dayKey': 'yesterday'}), isNull);
      expect(DietDayRecord.fromMap({'dayKey': '2026-09-25'}), isNull);
    });
  });

  group('FirestoreDietRepository — skip and status', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreDietRepository repo;
    final day = DateTime(2026, 9, 25);

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreDietRepository(
        firestore: firestore,
        // `currentUid` supplies the signed-in user; the changes stream is
        // broadcast-safe because this test opens several watches.
        uidSource: UidSource(
          currentUid: () => 'u1',
          uidChanges: const Stream<String?>.empty(),
        ),
      );
      await repo.savePlan(_plan());
      // Warms the active-plan cache the tick materialises its items from.
      await repo.watchActivePlan().firstWhere((p) => p != null);
    });

    Future<Map<String, dynamic>> entry() async => (await firestore
        .collection('users/u1/dietEntries')
        .doc('2026-09-25__meal-1')
        .get())
        .data()!;
    Future<int> logCount() async =>
        (await firestore.collection('users/u1/foodLogs').get()).docs.length;

    test('a tick writes status eaten; a skip un-ticks, removes the tick\'s '
        'foods and says why', () async {
      await repo.setMealEaten(mealId: 'meal-1', day: day, eaten: true);
      expect((await entry())['status'], 'eaten');
      expect(await logCount(), 2);

      await repo.setMealSkipped(mealId: 'meal-1', day: day, skipped: true);
      expect((await entry())['eaten'], isFalse);
      expect((await entry())['status'], 'skipped');
      expect(await logCount(), 0);
      expect(await repo.watchSkipped(day).first, {'meal-1'});
      expect(await repo.watchConsumed(day).first, isEmpty);

      // Changing their mind: ticking clears the skip.
      await repo.setMealEaten(mealId: 'meal-1', day: day, eaten: true);
      expect(await repo.watchSkipped(day).first, isEmpty);
      expect((await entry())['status'], 'eaten');
    });

    test('an un-skip leaves the meal unmarked', () async {
      await repo.setMealSkipped(mealId: 'meal-1', day: day, skipped: true);
      await repo.setMealSkipped(mealId: 'meal-1', day: day, skipped: false);
      expect((await entry())['status'], 'unmarked');
      expect(await repo.watchSkipped(day).first, isEmpty);
    });

    test('watchDietDays reads one record per day in the range, oldest '
        'first, and drops what it can\'t parse', () async {
      final record = Map<String, dynamic>.from(_vector()['record'] as Map);
      final days = firestore.collection('users/u1/dietDays');
      await days.doc('2026-09-25').set(record);
      await days.doc('2026-09-24').set({...record, 'dayKey': '2026-09-24'});
      await days.doc('2026-09-10').set({...record, 'dayKey': '2026-09-10'});
      await days.doc('2026-09-23').set({'dayKey': '2026-09-23'});
      final got = await repo
          .watchDietDays(from: DateTime(2026, 9, 20), to: day)
          .first;
      expect(got.map((r) => r.dayKey), ['2026-09-24', '2026-09-25']);
    });
  });

  group('Diet history screens', () {
    DietDayRecord recordFor(DateTime d) {
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return DietDayRecord.fromMap({
        ...Map<String, dynamic>.from(_vector()['record'] as Map),
        'dayKey': key,
      })!;
    }

    testWidgets('lists recorded days newest first, labelled relatively',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diet = InMemoryDietRepository()
        ..seedDietDays([
          recordFor(today.subtract(const Duration(days: 3))),
          recordFor(today.subtract(const Duration(days: 1))),
        ]);
      await tester.pumpWidget(_wrap(const DietHistoryPage(), diet));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.textContaining('2 of 4 meals'), findsNWidgets(2));
      expect(find.textContaining('1 skipped'), findsNWidgets(2));
      // A consumed figure never appears without its basis.
      expect(find.text('logged by you'), findsNWidgets(2));
      final rows = tester
          .widgetList<GestureDetector>(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'diet-history-day-',
                  ),
            ),
          )
          .map((w) => (w.key! as ValueKey<String>).value)
          .toList();
      expect(rows.first.compareTo(rows.last), greaterThan(0));
    });

    testWidgets('skipping from the meal page shows on the Diet screen, and '
        'the Diet screen opens the history', (tester) async {
      final diet = InMemoryDietRepository();
      await diet.savePlan(_plan());
      final lunch = _plan().days.single.meals.single;
      await tester.pumpWidget(
        _wrap(MealDetailPage(meal: lunch, isSupplement: false), diet),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-skip-action')));
      await tester.pumpAndSettle();
      expect(await diet.watchSkipped(DateTime.now()).first, {'meal-1'});
      expect(find.text('Skipped · Undo'), findsOneWidget);

      await tester.pumpWidget(_wrap(const DietPlanPage(), diet));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meal-skipped-meal-1')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('diet-history-row')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('diet-history-row')));
      await tester.pumpAndSettle();
      expect(find.byType(DietHistoryPage), findsOneWidget);
    });

    testWidgets('an empty history says so', (tester) async {
      await tester.pumpWidget(
        _wrap(const DietHistoryPage(), InMemoryDietRepository()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diet-history-empty')), findsOneWidget);
    });

    testWidgets('a past day shows each meal\'s status and flags a rebuilt '
        'plan', (tester) async {
      final record = recordFor(DateTime(2026, 9, 25));
      await tester.pumpWidget(
        _wrap(
          DietDayPage(record: record, title: 'Thu, Sep 25'),
          InMemoryDietRepository(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eaten'), findsOneWidget);
      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Not marked'), findsNWidgets(2));
      expect(find.byKey(const Key('diet-day-reconstructed')), findsOneWidget);
      expect(find.textContaining('of 2000 kcal target'), findsOneWidget);
    });
  });
}
