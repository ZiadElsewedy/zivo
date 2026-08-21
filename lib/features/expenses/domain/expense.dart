/// A single spend — an append-only log entity ("what happened").
///
/// [categoryId] is a raw reference into the open category set (built-ins +
/// user-created, see `expense_category.dart`) — resolving it to a displayable
/// `ExpenseCategory` is a presentation concern via `resolveCategory`, not this
/// layer's, so a category can be renamed or removed without rewriting history.
class Expense {
  const Expense({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.categoryId,
    required this.spentAt,
    this.note,
  });

  final String id;
  final int amountMinor; // integer minor units (e.g. piastres)
  final String currency; // e.g. "EGP"
  final String categoryId;
  final DateTime spentAt;
  final String? note;
}
