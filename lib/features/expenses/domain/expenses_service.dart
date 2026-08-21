import 'category_repository.dart';
import 'expense.dart';
import 'expense_category.dart';
import 'expense_repository.dart';
import 'wallet_repository.dart';

/// The single entry point features use for expenses. It composes the three
/// underlying repositories — the spend log, the wallet balance, and custom
/// categories — so the wallet stays in sync automatically: adding an expense
/// deducts it, editing adjusts by the delta, removing refunds it. Presentation
/// code should go through this instead of touching `ExpenseRepository`
/// directly (mirrors `MediaService` in `core/media/media_service.dart`, which
/// composes its own trio of repositories behind one facade).
class ExpensesService {
  ExpensesService({
    required this.expenses,
    required this.wallet,
    required this.categories,
  });

  final ExpenseRepository expenses;
  final WalletRepository wallet;
  final CategoryRepository categories;

  /// Built-ins + the user's custom categories, in that order.
  List<ExpenseCategory> allCategories() => [
    ...kBuiltInCategories,
    ...categories.current,
  ];

  /// Emits [allCategories] immediately, then again whenever custom categories
  /// change.
  Stream<List<ExpenseCategory>> watchCategories() =>
      categories.watchAll().map((custom) => [...kBuiltInCategories, ...custom]);

  Future<void> addExpense(Expense expense) async {
    await expenses.add(expense);
    await wallet.adjustBy(-expense.amountMinor);
  }

  Future<void> updateExpense(Expense oldExpense, Expense newExpense) async {
    await expenses.update(newExpense);
    final delta = oldExpense.amountMinor - newExpense.amountMinor;
    if (delta != 0) await wallet.adjustBy(delta);
  }

  Future<void> removeExpense(Expense expense) async {
    await expenses.remove(expense.id);
    await wallet.adjustBy(expense.amountMinor);
  }

  Future<void> setWalletBalance(int minor, {String currency = 'EGP'}) =>
      wallet.setBalance(minor, currency: currency);

  /// Adds funds to the wallet — "I just got paid" / "topping up my cash".
  Future<void> topUpWallet(int minor) => wallet.adjustBy(minor);

  Future<void> addCategory(ExpenseCategory category) => categories.add(category);
}
