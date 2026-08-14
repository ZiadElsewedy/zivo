import 'expense_category.dart';

/// A single spend — an append-only log entity ("what happened").
class Expense {
  const Expense({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.category,
    required this.spentAt,
    this.note,
  });

  final String id;
  final int amountMinor; // integer minor units (e.g. piastres)
  final String currency; // e.g. "EGP"
  final ExpenseCategory category;
  final DateTime spentAt;
  final String? note;
}
