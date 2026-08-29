import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/firestore_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/presentation/pages/expense_capture_page.dart';
import 'package:zivo/features/expenses/presentation/pages/expenses_list_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required InMemoryExpenseRepository expensesOverride,
  InMemoryWalletRepository? walletOverride,
  InMemoryCategoryRepository? categoriesOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: expensesOverride,
    wallet: walletOverride ?? InMemoryWalletRepository(),
    expenseCategories: categoriesOverride ?? InMemoryCategoryRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'expenses render grouped by day, newest first, with a summary header',
    (tester) async {
      // Taller than the default test surface: the wallet card, first-run
      // prompt, and category breakdown push the day-grouped log down enough
      // that the default viewport wouldn't build the later rows at all.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final expenses = InMemoryExpenseRepository();
      addTearDown(expenses.dispose);

      final now = DateTime.now();
      await expenses.add(
        Expense(
          id: 'lunch',
          amountMinor: 5000,
          currency: 'EGP',
          categoryId: 'food',
          spentAt: now,
          note: 'Team lunch',
        ),
      );
      await expenses.add(
        Expense(
          id: 'coffee',
          amountMinor: 2500,
          currency: 'EGP',
          categoryId: 'coffee',
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

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);

      // Group order: Today before Yesterday.
      final todayY = tester.getTopLeft(find.text('TODAY')).dy;
      final yesterdayY = tester.getTopLeft(find.text('YESTERDAY')).dy;
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

    await tester.tap(find.byKey(const Key('new-expense-fab')));
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
        categoryId: 'groceries',
        spentAt: DateTime.now(),
        note: 'Weekly shop',
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
    );
    await tester.pump();

    // The wallet header pushes the list below the default test viewport.
    await tester.scrollUntilVisible(
      find.text('Weekly shop'),
      200,
      scrollable: find.byType(Scrollable).first,
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
        categoryId: 'transport',
        spentAt: DateTime.now(),
        note: 'Uber',
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const ExpensesListPage(), expensesOverride: expenses),
    );
    await tester.pump();

    expect(expenses.current.any((e) => e.id == 'to-delete'), isTrue);

    // Bring the row into the viewport before the swipe — the wallet header
    // pushes the list below the default test viewport.
    await tester.scrollUntilVisible(
      find.text('Uber'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
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
        wallet: InMemoryWalletRepository(),
        expenseCategories: InMemoryCategoryRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        child: const MaterialApp(home: ExpensesListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing spent yet — a calm start.'), findsOneWidget);
  });

  testWidgets('setting a wallet balance then adding an expense deducts it', (
    tester,
  ) async {
    final expenses = InMemoryExpenseRepository();
    addTearDown(expenses.dispose);
    final wallet = InMemoryWalletRepository();
    addTearDown(wallet.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const ExpensesListPage(),
        expensesOverride: expenses,
        walletOverride: wallet,
      ),
    );
    await tester.pump();

    // First run: the setup prompt, not a balance.
    expect(find.text('Set starting balance'), findsOneWidget);

    await tester.tap(find.text('Set starting balance'));
    await tester.pumpAndSettle();

    for (final digit in ['1', '0', '0', '0']) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.tap(find.text('Save balance'));
    await tester.pumpAndSettle();

    expect(find.text('1000'), findsWidgets); // balance figure; 'EGP' is its own unit

    // Logging an expense through the real capture flow deducts it from the
    // wallet automatically.
    await tester.tap(find.byKey(const Key('new-expense-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('4'));
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('Save · 45 EGP'));
    await tester.pumpAndSettle();

    expect(find.text('955'), findsWidgets);
  });
}
