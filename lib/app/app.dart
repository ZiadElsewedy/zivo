import 'package:flutter/material.dart';

import '../core/scope/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../features/expenses/data/in_memory_expense_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/shell/presentation/home_shell.dart';
import '../features/tasks/data/in_memory_task_repository.dart';
import '../features/tasks/domain/task_repository.dart';

/// The ZIVO application root. Owns shared repositories (in-memory for now)
/// and exposes them via [AppScope].
class ZivoApp extends StatefulWidget {
  const ZivoApp({super.key});

  @override
  State<ZivoApp> createState() => _ZivoAppState();
}

class _ZivoAppState extends State<ZivoApp> {
  final ExpenseRepository _expenses = InMemoryExpenseRepository();
  final TaskRepository _tasks = InMemoryTaskRepository();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      expenses: _expenses,
      tasks: _tasks,
      child: MaterialApp(
        title: 'ZIVO',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const HomeShell(),
      ),
    );
  }
}
