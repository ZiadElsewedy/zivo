import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/firestore_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_category.dart';
import 'package:zivo/features/expenses/presentation/pages/expense_capture_page.dart';
import 'package:zivo/features/expenses/presentation/pages/expenses_list_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required InMemoryExpenseRepository expensesOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: expensesOverride,
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'expenses render grouped by day, newest first, with a summary header',
    (tester) async {
      final expenses = InMemoryExpenseRepository();
      addTearDown(expenses.dispose);

      final now = DateTime.now();
      await expenses.add(
        Expense(
          id: 'lunch',
          amountMinor: 5000,
          currency: 'EGP',
          category: ExpenseCategory.food,
          spentAt: now,
          note: 'Team lunch',
        ),
      );
      await expenses.add(
        Expense(
          id: 'coffee',
          amountMinor: 2500,
          currency: 'EGP',
          category: ExpenseCategory.coffee,
          spentAt: now.subtract(const Duration(days: 1)),
          note: 'Espresso run',
        ),
      );

      await tester.pumpWidget(
        _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
      );
      await tester.pump();

      // Both newly added expenses render, grouped under the right day.
      expect(find.text('Team lunch'), findsOneWidget);
      expect(find.text('Espresso run'), findsOneWidget);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);

      // Group order: Today before Yesterday.
      final todayY = tester.getTopLeft(find.text('Today')).dy;
      final yesterdayY = tester.getTopLeft(find.text('Yesterday')).dy;
      expect(todayY, lessThan(yesterdayY));

      // Today's row sits above yesterday's row.
      final lunchY = tester.getTopLeft(find.text('Team lunch')).dy;
      final coffeeY = tester.getTopLeft(find.text('Espresso run')).dy;
      expect(lunchY, lessThan(coffeeY));
    },
  );

  testWidgets('the FAB opens the capture page for a new expense', (
    tester,
  ) async {
    final expenses = InMemoryExpenseRepository();
    addTearDown(expenses.dispose);

    await tester.pumpWidget(
      _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseCapturePage), findsOneWidget);
    expect(find.text('New expense'), findsOneWidget);
  });

  testWidgets('tapping a row opens it for editing, prefilled', (
    tester,
  ) async {
    final expenses = InMemoryExpenseRepository();
    addTearDown(expenses.dispose);

    await expenses.add(
      Expense(
        id: 'groceries-run',
        amountMinor: 8000,
        currency: 'EGP',
        category: ExpenseCategory.groceries,
        spentAt: DateTime.now(),
        note: 'Weekly shop',
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
    );
    await tester.pump();

    await tester.tap(find.text('Weekly shop'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseCapturePage), findsOneWidget);
    expect(find.text('Edit expense'), findsOneWidget);
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
  });

  testWidgets('swiping a row deletes it via the repository', (tester) async {
    final expenses = InMemoryExpenseRepository();
    addTearDown(expenses.dispose);

    await expenses.add(
      Expense(
        id: 'to-delete',
        amountMinor: 1500,
        currency: 'EGP',
        category: ExpenseCategory.transport,
        spentAt: DateTime.now(),
        note: 'Uber',
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
    );
    await tester.pump();

    expect(expenses.current.any((e) => e.id == 'to-delete'), isTrue);

    await tester.drag(find.text('Uber'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(expenses.current.any((e) => e.id == 'to-delete'), isFalse);
  });

  testWidgets('shows the empty state when there are no expenses', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final expenses = FirestoreExpenseRepository(
      firestore: firestore,
      uidSource: UidSource(
        currentUid: () => 'test-uid',
        uidChanges: Stream.value('test-uid'),
      ),
    );

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: expenses,
        tasks: InMemoryTaskRepository(),
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        child: const MaterialApp(home: ExpensesListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing spent yet — a calm start.'), findsOneWidget);
  });
}
