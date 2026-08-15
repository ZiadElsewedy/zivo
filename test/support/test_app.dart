import 'package:flutter/material.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/auth/domain/auth_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import 'fake_auth_repository.dart';

/// Wraps [child] in an [AppScope] (fake auth + fresh in-memory repos) and a
/// [MaterialApp], for widget tests that need the full DI seam.
Widget wrapWithScope(Widget child, {AuthRepository? auth}) {
  return AppScope(
    auth: auth ?? FakeAuthRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    child: MaterialApp(home: child),
  );
}
