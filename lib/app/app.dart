import 'package:flutter/material.dart';

import '../core/scope/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../features/expenses/data/in_memory_expense_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/shell/presentation/home_shell.dart';

/// The ZIVO application root. Owns shared repositories (in-memory for now)
/// and exposes them via [AppScope].
class ZivoApp extends StatefulWidget {
  const ZivoApp({super.key});

  @override
  State<ZivoApp> createState() => _ZivoAppState();
}

class _ZivoAppState extends State<ZivoApp> {
  final ExpenseRepository _expenses = InMemoryExpenseRepository();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      expenses: _expenses,
      child: MaterialApp(
        title: 'ZIVO',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const HomeShell(),
      ),
    );
  }
}
