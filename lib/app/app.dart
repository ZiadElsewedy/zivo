import 'package:flutter/material.dart';

import '../core/scope/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/data/firestore_profile_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/profile_repository.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/expenses/data/in_memory_expense_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/moments/data/in_memory_moment_repository.dart';
import '../features/moments/domain/moment_repository.dart';
import '../features/notes/data/in_memory_note_repository.dart';
import '../features/notes/domain/note_repository.dart';
import '../features/schedule/data/in_memory_schedule_repository.dart';
import '../features/schedule/domain/schedule_repository.dart';
import '../features/tasks/data/in_memory_task_repository.dart';
import '../features/tasks/domain/task_repository.dart';
import '../features/workout/data/in_memory_workout_repository.dart';
import '../features/workout/domain/workout_repository.dart';

/// The ZIVO application root. Owns shared repositories and exposes them via
/// [AppScope]. The feature repositories are still in-memory; only [auth] is
/// backed by a real backend (Firebase).
///
/// Repositories are injectable (defaulting to the real implementations) so
/// tests can supply fakes — e.g. a pre-authenticated auth repo to exercise the
/// app shell without touching Firebase.
class ZivoApp extends StatefulWidget {
  const ZivoApp({
    this.auth,
    this.profiles,
    this.expenses,
    this.tasks,
    this.schedule,
    this.notes,
    this.moments,
    this.workouts,
    super.key,
  });

  final AuthRepository? auth;
  final ProfileRepository? profiles;
  final ExpenseRepository? expenses;
  final TaskRepository? tasks;
  final ScheduleRepository? schedule;
  final NoteRepository? notes;
  final MomentRepository? moments;
  final WorkoutRepository? workouts;

  @override
  State<ZivoApp> createState() => _ZivoAppState();
}

class _ZivoAppState extends State<ZivoApp> {
  late final AuthRepository _auth = widget.auth ?? FirebaseAuthRepository();
  late final ProfileRepository _profiles =
      widget.profiles ?? FirestoreProfileRepository();
  late final ExpenseRepository _expenses =
      widget.expenses ?? InMemoryExpenseRepository();
  late final TaskRepository _tasks = widget.tasks ?? InMemoryTaskRepository();
  late final ScheduleRepository _schedule =
      widget.schedule ?? InMemoryScheduleRepository();
  late final NoteRepository _notes = widget.notes ?? InMemoryNoteRepository();
  late final MomentRepository _moments =
      widget.moments ?? InMemoryMomentRepository();
  late final WorkoutRepository _workouts =
      widget.workouts ?? InMemoryWorkoutRepository();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: _auth,
      profiles: _profiles,
      expenses: _expenses,
      tasks: _tasks,
      schedule: _schedule,
      notes: _notes,
      moments: _moments,
      workouts: _workouts,
      child: MaterialApp(
        title: 'ZIVO',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}
