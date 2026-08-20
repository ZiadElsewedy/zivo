import 'package:flutter/widgets.dart';

import '../media/media_service.dart';
import '../../features/ai/domain/ai_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/diet/domain/diet_repository.dart';
import '../../features/expenses/domain/expense_repository.dart';
import '../../features/moments/domain/moment_repository.dart';
import '../../features/notes/domain/note_repository.dart';
import '../../features/schedule/domain/schedule_repository.dart';
import '../../features/tasks/domain/task_repository.dart';
import '../../features/university/domain/university_repository.dart';
import '../../features/workout/domain/workout_plan_repository.dart';
import '../../features/workout/domain/workout_repository.dart';
import '../../features/workout/domain/workout_session_repository.dart';

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
    required this.workoutPlans,
    required this.workoutSessions,
    required this.university,
    required this.diet,
    required this.ai,
    this.media,
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
  final WorkoutPlanRepository workoutPlans;
  final WorkoutSessionRepository workoutSessions;
  final UniversityRepository university;
  final DietRepository diet;

  /// The AI assistant ("Ask") seam. Today's default is a pure in-memory
  /// `FakeAiRepository`; the real Firestore + `aiChat` gateway impl arrives
  /// once the server half is built and deployed.
  final AiRepository ai;

  /// The media pipeline: durable local storage of captured photos, per-account
  /// backup fan-out (Photos now, Drive next), read-side resolution, and — via
  /// [MediaService.preferences] — the account's storage choices surfaced in
  /// Settings. Every feature that captures or displays media goes through this
  /// instead of touching files or Firebase Storage directly.
  ///
  /// Optional so the many widget tests that don't exercise media can keep
  /// constructing a scope without it; production and media-page tests always
  /// provide one. Read it through [requireMedia] from media-bearing pages.
  final MediaService? media;

  /// The media pipeline, asserting it was provided. Use from pages that capture
  /// or display media (Moments, Profile, Settings) — production always wires it.
  MediaService get requireMedia {
    assert(media != null, 'AppScope.media was not provided to this scope');
    return media!;
  }

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
      workoutPlans != oldWidget.workoutPlans ||
      workoutSessions != oldWidget.workoutSessions ||
      university != oldWidget.university ||
      diet != oldWidget.diet ||
      ai != oldWidget.ai ||
      media != oldWidget.media;
}
