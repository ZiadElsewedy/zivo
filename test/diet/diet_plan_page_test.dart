import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose `watchActivePlan()` stream only emits when [emit] is
/// called, so tests can assert on the in-between "waiting" state
/// deterministically.
class _PendingDietRepository implements DietRepository {
  final StreamController<DietPlan?> _controller = StreamController<DietPlan?>.broadcast();

  @override
  DietPlan? get activePlan => null;

  @override
  Stream<DietPlan?> watchActivePlan() => _controller.stream;

  @override
  Future<void> savePlan(DietPlan plan) async {}

  @override
  Future<void> deletePlan(String id) async {}

  @override
  Stream<Set<String>> watchConsumed(DateTime day) => Stream.value(const <String>{});

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) async {}

  void emit(DietPlan? plan) => _controller.add(plan);

  void dispose() => _controller.close();
}

Widget _wrap({required Widget child, required DietRepository dietOverride}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    university: InMemoryUniversityRepository(),
    diet: dietOverride,
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Diet plan page renders the seeded plan and marks a meal eaten', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();

    // Seeded meals and items render.
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Chicken breast'), findsOneWidget);

    // Tapping the Lunch card marks it eaten reactively.
    await tester.tap(find.text('Lunch'));
    await tester.pump();

    final consumed = await diet.watchConsumed(DateTime.now()).first;
    expect(consumed, contains('seed-meal-lunch'));
  });

  testWidgets('shows a spinner while the plan stream is waiting, then the plan', (tester) async {
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No diet plan yet.'), findsNothing);
    // No FAB while the real active plan isn't known yet.
    expect(find.byType(FloatingActionButton), findsNothing);

    diet.emit(
      DietPlan(
        id: 'p1',
        name: 'Cut',
        status: DietPlanStatus.active,
        source: DietSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        days: const [],
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cut'), findsOneWidget);
  });

  testWidgets('shows the empty state once the plan stream settles with no data', (tester) async {
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));

    diet.emit(null);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No diet plan yet.'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('deleting the plan from the editor returns to the empty state', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();

    // Open the editor for the existing (seeded) plan via the FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diet-plan-delete')), findsOneWidget);
    await tester.tap(find.byKey(const Key('diet-plan-delete')));
    await tester.pumpAndSettle();

    // Confirm dialog appears; confirm the delete.
    expect(find.text('Delete this plan?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(diet.activePlan, isNull);
    expect(find.text('No diet plan yet.'), findsOneWidget);
  });
}
