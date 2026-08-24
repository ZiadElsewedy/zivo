import 'package:flutter/widgets.dart';

import '../media/media_service.dart';
import '../../features/ai/data/audio_recorder.dart';
import '../../features/ai/domain/ai_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/profile_repository.dart';
import '../../features/diet/domain/diet_repository.dart';
import '../../features/expenses/domain/category_repository.dart';
import '../../features/expenses/domain/expense_repository.dart';
import '../../features/expenses/domain/expenses_service.dart';
import '../../features/expenses/domain/wallet_repository.dart';
import '../../features/moments/domain/moment_repository.dart';
import '../../features/workout/domain/body_weight_repository.dart';
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
    this.wallet,
    this.expenseCategories,
    required this.moments,
    required this.workouts,
    required this.workoutPlans,
    required this.workoutSessions,
    this.bodyWeight,
    required this.diet,
    required this.ai,
    this.recorder,
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

  /// The wallet balance, and the user's custom expense categories on top of
  /// the app's built-in set. Optional for the same reason [media] is: many
  /// widget tests build a scope without touching Expenses. Production and
  /// the Expenses-page tests always provide both — read them through
  /// [requireWallet] / [requireCategories], or via [expensesService].
  final WalletRepository? wallet;
  final CategoryRepository? expenseCategories;

  final MomentRepository moments;
  final WorkoutRepository workouts;
  final WorkoutPlanRepository workoutPlans;
  final WorkoutSessionRepository workoutSessions;

  /// Logged bodyweight entries — the Workout Dashboard's weight-over-time
  /// track, independent of any single training session.
  ///
  /// Optional so the many widget tests that don't exercise the dashboard can
  /// keep constructing a scope without it; production and dashboard tests
  /// always provide one. Read it through [requireBodyWeight].
  final BodyWeightRepository? bodyWeight;
  final DietRepository diet;

  /// The AI assistant ("Ask") seam. Today's default is a pure in-memory
  /// `FakeAiRepository`; the real Firestore + `aiChat` gateway impl arrives
  /// once the server half is built and deployed.
  final AiRepository ai;

  /// The composer's voice-note recorder — `record`-backed in production.
  ///
  /// Optional so the many widget tests that don't exercise the mic button can
  /// keep constructing a scope without it; production and Ask-page mic tests
  /// always provide one. Read it through [requireRecorder].
  final AudioRecorderService? recorder;

  /// The composer's voice-note recorder, asserting it was provided. Use from
  /// the Ask page's mic button — production always wires it.
  AudioRecorderService get requireRecorder {
    assert(
      recorder != null,
      'AppScope.recorder was not provided to this scope',
    );
    return recorder!;
  }

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

  WalletRepository get requireWallet {
    assert(wallet != null, 'AppScope.wallet was not provided to this scope');
    return wallet!;
  }

  CategoryRepository get requireCategories {
    assert(
      expenseCategories != null,
      'AppScope.expenseCategories was not provided to this scope',
    );
    return expenseCategories!;
  }

  /// The Expenses feature's composed seam (log + wallet + categories). Built
  /// on demand — cheap, since it holds no state of its own.
  ExpensesService get expensesService => ExpensesService(
    expenses: expenses,
    wallet: requireWallet,
    categories: requireCategories,
  );

  /// The bodyweight repository, asserting it was provided. Use from the
  /// Workout Dashboard — production always wires it.
  BodyWeightRepository get requireBodyWeight {
    assert(
      bodyWeight != null,
      'AppScope.bodyWeight was not provided to this scope',
    );
    return bodyWeight!;
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
      wallet != oldWidget.wallet ||
      expenseCategories != oldWidget.expenseCategories ||
      moments != oldWidget.moments ||
      workouts != oldWidget.workouts ||
      workoutPlans != oldWidget.workoutPlans ||
      workoutSessions != oldWidget.workoutSessions ||
      bodyWeight != oldWidget.bodyWeight ||
      diet != oldWidget.diet ||
      ai != oldWidget.ai ||
      recorder != oldWidget.recorder ||
      media != oldWidget.media;
}
