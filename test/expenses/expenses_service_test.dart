import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_category.dart';
import 'package:zivo/features/expenses/domain/expenses_service.dart';

Expense _expense(String id, int amountMinor, {String categoryId = 'food'}) => Expense(
  id: id,
  amountMinor: amountMinor,
  currency: 'EGP',
  categoryId: categoryId,
  spentAt: DateTime(2026, 1, 1),
);

void main() {
  late InMemoryExpenseRepository expenses;
  late InMemoryWalletRepository wallet;
  late InMemoryCategoryRepository categories;
  late ExpensesService service;

  setUp(() async {
    expenses = InMemoryExpenseRepository();
    // InMemoryExpenseRepository seeds demo data in its constructor; clear it
    // so this service-logic test starts from a clean, empty log.
    for (final seeded in List.of(expenses.current)) {
      await expenses.remove(seeded.id);
    }
    wallet = InMemoryWalletRepository();
    categories = InMemoryCategoryRepository();
    service = ExpensesService(expenses: expenses, wallet: wallet, categories: categories);
  });

  tearDown(() {
    expenses.dispose();
    wallet.dispose();
    categories.dispose();
  });

  test('addExpense logs it and deducts the amount from the wallet', () async {
    await wallet.setBalance(10000);

    await service.addExpense(_expense('e1', 4500));

    expect(expenses.current.single.id, 'e1');
    expect(wallet.current!.balanceMinor, 5500);
  });

  test('addExpense with no wallet set up just logs it (no crash)', () async {
    await service.addExpense(_expense('e1', 4500));

    expect(expenses.current.single.id, 'e1');
    expect(wallet.current, isNull);
  });

  test('updateExpense adjusts the wallet by the delta', () async {
    await wallet.setBalance(10000);
    final original = _expense('e1', 4500);
    await service.addExpense(original);
    expect(wallet.current!.balanceMinor, 5500);

    // Correcting the amount up should deduct the extra 1000.
    await service.updateExpense(original, _expense('e1', 5500));
    expect(wallet.current!.balanceMinor, 4500);
  });

  test('removeExpense refunds the wallet', () async {
    await wallet.setBalance(10000);
    final expense = _expense('e1', 4500);
    await service.addExpense(expense);

    await service.removeExpense(expense);

    expect(expenses.current, isEmpty);
    expect(wallet.current!.balanceMinor, 10000);
  });

  test('overspending is allowed and the balance goes negative', () async {
    await wallet.setBalance(1000);

    await service.addExpense(_expense('e1', 4500));

    expect(wallet.current!.balanceMinor, -3500);
  });

  test('allCategories merges built-ins with custom categories', () async {
    expect(service.allCategories(), kBuiltInCategories);

    const custom = ExpenseCategory(
      id: 'subs',
      label: 'Subscriptions',
      icon: CategoryIcon.entertainment,
    );
    await service.addCategory(custom);

    expect(service.allCategories(), [...kBuiltInCategories, custom]);
  });
}
