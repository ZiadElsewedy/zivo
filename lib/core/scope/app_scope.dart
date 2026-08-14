import 'package:flutter/widgets.dart';

import '../../features/expenses/domain/expense_repository.dart';

/// Provides shared repositories to the widget tree. A deliberately tiny
/// seam for now; it will be replaced by a proper DI container (get_it) when
/// the foundation phase lands. Kept above the app's Navigator so pushed
/// routes can resolve it.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.expenses,
    required super.child,
    super.key,
  });

  final ExpenseRepository expenses;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      expenses != oldWidget.expenses;
}
