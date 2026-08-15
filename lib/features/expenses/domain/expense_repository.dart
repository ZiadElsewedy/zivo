import 'expense.dart';

/// The seam between the app and expense storage. Today it is backed by an
/// in-memory demo store; later a Firestore-backed implementation slots in
/// behind this same interface without touching the presentation layer.
abstract interface class ExpenseRepository {
  /// Latest snapshot (synchronous, for initial paint).
  List<Expense> get current;

  /// Emits the current list immediately, then again on every change.
  Stream<List<Expense>> watchAll();

  /// Appends a new expense.
  Future<void> add(Expense expense);

  /// Replaces an existing expense (matched by id) in place.
  Future<void> update(Expense expense);

  /// Removes an expense by id.
  Future<void> remove(String id);
}

/// Sum of expenses on the same calendar day as [now].
int todayTotalMinor(List<Expense> expenses, DateTime now) => expenses
    .where((e) =>
        e.spentAt.year == now.year &&
        e.spentAt.month == now.month &&
        e.spentAt.day == now.day)
    .fold(0, (sum, e) => sum + e.amountMinor);

/// Sum of expenses within the trailing 7 days. (A rolling window for the demo;
/// a tz-pinned calendar week arrives with the real rollup logic.)
int weekTotalMinor(List<Expense> expenses, DateTime now) {
  final from = now.subtract(const Duration(days: 7));
  return expenses
      .where((e) => e.spentAt.isAfter(from))
      .fold(0, (sum, e) => sum + e.amountMinor);
}
