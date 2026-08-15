import 'package:flutter/widgets.dart';

import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/diet/domain/diet_repository.dart';
import '../../features/expenses/domain/expense_repository.dart';
import '../../features/moments/domain/moment_repository.dart';
import '../../features/notes/domain/note_repository.dart';
import '../../features/schedule/domain/schedule_repository.dart';
import '../../features/tasks/domain/task_repository.dart';
import '../../features/university/domain/university_repository.dart';
import '../../features/workout/domain/workout_repository.dart';

/// Provides shared repositories to the widget tree. A deliberately tiny
/// seam for now; it will be replaced by a proper DI container (get_it) when
/// the foundation phase lands. Kept above the app's Navigator so pushed
/// routes can resolve it.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.auth,
    required this.profiles,
    required this.expenses,
    required this.tasks,
    required this.schedule,
    required this.notes,
    required this.moments,
    required this.workouts,
    required this.university,
    required this.diet,
    required super.child,
    super.key,
  });

  /// The authentication backend. Its signed-in `uid` is the app's canonical
  /// identity (and the future Firestore ownership key).
  final AuthRepository auth;

  /// Persists the signed-in user's [UserProfile] (`users/{uid}` in Firestore).
  final ProfileRepository profiles;
  final ExpenseRepository expenses;
  final TaskRepository tasks;
  final ScheduleRepository schedule;
  final NoteRepository notes;
  final MomentRepository moments;
  final WorkoutRepository workouts;
  final UniversityRepository university;
  final DietRepository diet;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      auth != oldWidget.auth ||
      profiles != oldWidget.profiles ||
      expenses != oldWidget.expenses ||
      tasks != oldWidget.tasks ||
      schedule != oldWidget.schedule ||
      notes != oldWidget.notes ||
      moments != oldWidget.moments ||
      workouts != oldWidget.workouts ||
      university != oldWidget.university ||
      diet != oldWidget.diet;
}
