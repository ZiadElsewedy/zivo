/// Expense categories. Kept small and personal — money is Solar throughout.
enum ExpenseCategory { food, coffee, transport, groceries, other }

extension ExpenseCategoryX on ExpenseCategory {
  String get label => switch (this) {
        ExpenseCategory.food => 'Food',
        ExpenseCategory.coffee => 'Coffee',
        ExpenseCategory.transport => 'Transport',
        ExpenseCategory.groceries => 'Groceries',
        ExpenseCategory.other => 'Other',
      };

  /// A leading glyph for chips; empty for the catch-all.
  String get emoji => switch (this) {
        ExpenseCategory.food => '🍔',
        ExpenseCategory.coffee => '☕',
        ExpenseCategory.transport => '🚕',
        ExpenseCategory.groceries => '🛒',
        ExpenseCategory.other => '',
      };
}
