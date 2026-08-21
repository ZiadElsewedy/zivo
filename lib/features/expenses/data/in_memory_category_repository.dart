import 'dart:async';

import '../domain/category_repository.dart';
import '../domain/expense_category.dart';

/// Demo store: keeps the user's custom categories in memory.
class InMemoryCategoryRepository implements CategoryRepository {
  final List<ExpenseCategory> _items = [];
  final StreamController<List<ExpenseCategory>> _controller =
      StreamController<List<ExpenseCategory>>.broadcast();

  @override
  List<ExpenseCategory> get current => List.unmodifiable(_items);

  @override
  Stream<List<ExpenseCategory>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(ExpenseCategory category) async {
    _items.add(category);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
