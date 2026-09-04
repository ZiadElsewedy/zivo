import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_repository.dart';
import 'package:zivo/features/expenses/domain/wallet.dart';
import 'package:zivo/features/expenses/domain/wallet_repository.dart';
import 'package:zivo/features/expenses/presentation/pages/expense_capture_page.dart';
import 'package:zivo/features/expenses/presentation/widgets/amount_keypad.dart';
import 'package:zivo/features/expenses/presentation/widgets/wallet_balance_sheet.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Regression cover for the capture flows' **save re-entrancy** guard.
///
/// Each `_save` is async and the button stayed live across the await, so a
/// second tap ran the whole handler again before the first one's write and
/// `pop` landed. The failure was not a harmless repeat: a new expense/moment
/// mints its id from `microsecondsSinceEpoch` *per call*, so the second tap
/// wrote a second row rather than overwriting the first — and `topUpWallet` is
/// additive, so the wallet was credited twice with nothing on screen to show
/// it. Mirrors `live_session_page_test.dart`'s "rapid double-tap on Finish".
Widget _wrap({
  required Widget child,
  required ExpenseRepository expenses,
  WalletRepository? wallet,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: expenses,
    wallet: wallet ?? InMemoryWalletRepository(),
    expenseCategories: InMemoryCategoryRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// An expense store whose writes **hang** until [release] is called.
///
/// This is the whole point of the test: with a store that completes its write
/// immediately, the first tap's `await` resolves and the page pops before a
/// second tap could ever land, so the bug cannot reproduce and the test would
/// pass against the unguarded code. Holding the write open reproduces the real
/// condition — a button still on screen and still live while a write is in
/// flight.
class _BlockingExpenseRepository implements ExpenseRepository {
  _BlockingExpenseRepository(this._inner);

  final InMemoryExpenseRepository _inner;
  final List<Completer<void>> _pending = [];

  /// Every write attempt that reached the repository — the count the guard is
  /// meant to hold at one.
  int writes = 0;

  void release() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
  }

  @override
  List<Expense> get current => _inner.current;

  @override
  Stream<List<Expense>> watchAll() => _inner.watchAll();

  @override
  Future<void> add(Expense expense) async {
    writes++;
    final gate = Completer<void>();
    _pending.add(gate);
    await gate.future;
    await _inner.add(expense);
  }

  @override
  Future<void> update(Expense expense) => _inner.update(expense);

  @override
  Future<void> remove(String id) => _inner.remove(id);
}

/// The wallet equivalent of [_BlockingExpenseRepository]. `adjustBy` is
/// **additive**, so an unguarded double-tap credits the balance twice with no
/// duplicate row on screen to reveal it.
class _BlockingWalletRepository implements WalletRepository {
  _BlockingWalletRepository(this._inner);

  final InMemoryWalletRepository _inner;
  final List<Completer<void>> _pending = [];

  int adjustments = 0;

  void release() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
  }

  @override
  Wallet? get current => _inner.current;

  @override
  Stream<Wallet?> watch() => _inner.watch();

  @override
  Future<void> setBalance(int minor, {String currency = 'EGP'}) =>
      _inner.setBalance(minor, currency: currency);

  @override
  Future<void> adjustBy(int deltaMinor) async {
    adjustments++;
    final gate = Completer<void>();
    _pending.add(gate);
    await gate.future;
    await _inner.adjustBy(deltaMinor);
  }
}

/// A keypad digit, not the same glyph in the amount display above it.
Finder _key(String digit) =>
    find.descendant(of: find.byType(AmountKeypad), matching: find.text(digit));

void main() {
  testWidgets(
    'rapid double-tap on Save writes exactly one expense (not one per tap)',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inner = InMemoryExpenseRepository();
      addTearDown(inner.dispose);
      final expenses = _BlockingExpenseRepository(inner);
      final before = expenses.current.length;

      await tester.pumpWidget(
        _wrap(child: const ExpenseCapturePage(), expenses: expenses),
      );
      await tester.pump();

      await tester.tap(_key('5'));
      await tester.pump();

      // Tap, then tap again while the first write is still in flight — the
      // impatient double-tap, with the button still on screen because the page
      // cannot pop until its write returns.
      final save = find.textContaining('Save ·');
      expect(save, findsOneWidget);
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();

      expect(
        expenses.writes,
        1,
        reason: 'the second tap must be swallowed by the re-entrancy guard',
      );

      expenses.release();
      await tester.pumpAndSettle();

      expect(expenses.current.length, before + 1);
    },
  );

  testWidgets('rapid double-tap on Add funds tops the wallet up once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final expenses = InMemoryExpenseRepository();
    addTearDown(expenses.dispose);
    final inner = InMemoryWalletRepository();
    await inner.setBalance(0);
    final wallet = _BlockingWalletRepository(inner);

    await tester.pumpWidget(
      _wrap(
        expenses: expenses,
        wallet: wallet,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => WalletBalanceSheet.show(
              context,
              mode: WalletSheetMode.topUp,
              currency: 'EGP',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(_key('5'));
    await tester.pump();

    final add = find.descendant(
      of: find.byType(WalletBalanceSheet),
      matching: find.byType(InkWell),
    );
    await tester.tap(add.last);
    await tester.pump();
    await tester.tap(add.last, warnIfMissed: false);
    await tester.pump();

    expect(
      wallet.adjustments,
      1,
      reason: 'an additive top-up must not be applied twice',
    );

    wallet.release();
    await tester.pumpAndSettle();

    // 5 on the keypad is 5 major units — credited once, not twice.
    expect(wallet.current?.balanceMinor, 500);
  });
}
