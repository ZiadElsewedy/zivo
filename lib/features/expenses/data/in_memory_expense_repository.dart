import 'dart:async';

import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_repository.dart';

/// Demo store: keeps expenses in memory and broadcasts changes. Seeded so
/// Today opens at 45 EGP today / 685 EGP this week, matching the design.
class InMemoryExpenseRepository implements ExpenseRepository {
  InMemoryExpenseRepository() {
    _seed();
  }

  final List<Expense> _items = [];
  final StreamController<List<Expense>> _controller =
      StreamController<List<Expense>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      Expense(
        id: 'seed-1',
        amountMinor: 4500,
        currency: 'EGP',
        category: ExpenseCategory.coffee,
        spentAt: now.subtract(const Duration(hours: 1)),
      ),
      Expense(
        id: 'seed-2',
        amountMinor: 12000,
        currency: 'EGP',
        category: ExpenseCategory.groceries,
        spentAt: now.subtract(const Duration(days: 1)),
      ),
      Expense(
        id: 'seed-3',
        amountMinor: 9000,
        currency: 'EGP',
        category: ExpenseCategory.transport,
        spentAt: now.subtract(const Duration(days: 2)),
      ),
      Expense(
        id: 'seed-4',
        amountMinor: 22000,
        currency: 'EGP',
        category: ExpenseCategory.food,
        spentAt: now.subtract(const Duration(days: 3)),
      ),
      Expense(
        id: 'seed-5',
        amountMinor: 21000,
        currency: 'EGP',
        category: ExpenseCategory.food,
        spentAt: now.subtract(const Duration(days: 4)),
      ),
    ]);
  }

  @override
  List<Expense> get current => List.unmodifiable(_items);

  @override
  Stream<List<Expense>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(Expense expense) async {
    _items.insert(0, expense);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
