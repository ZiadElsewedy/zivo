import 'expense_category.dart';

/// The seam between the app and the user's *custom* categories. Built-ins
/// (see [kBuiltInCategories]) are not stored here — this only holds what the
/// user has added on top.
abstract interface class CategoryRepository {
  /// Latest snapshot (synchronous, for initial paint).
  List<ExpenseCategory> get current;

  /// Emits the current list immediately, then again on every change.
  Stream<List<ExpenseCategory>> watchAll();

  /// Adds a new custom category. The caller assigns [category.id].
  Future<void> add(ExpenseCategory category);
}
