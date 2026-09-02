// THROWAWAY preview entrypoint — a visual walkthrough of the Live Session,
// nothing more. Boots straight into `LiveSessionPage` on a seeded plan with
// the fake music controller connected, so the whole screen (warm-up →
// logging → rest → complete) can be looked at on a simulator without a
// backend, a plan, or Spotify.
//
//   flutter run -t test/manual/live_session_preview.dart \
//     --dart-define=USE_FIRESTORE=false -d <simulator-udid>
//
// Not part of the test suite.
import 'package:flutter/material.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_theme.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/music/data/fake_music_controller.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

PlannedExercise _exercise(
  int order,
  String name,
  String muscle,
  double weight,
) => PlannedExercise(
  id: 'e$order',
  name: name,
  order: order,
  muscleGroup: muscle,
  defaultRestSeconds: 90,
  sets: [
    for (var i = 0; i < 4; i++)
      PlannedSet(
        order: i,
        repTarget: const RepTarget.range(8, 12),
        restSeconds: 90,
        targetWeightKg: weight,
        type: SetType.working,
      ),
  ],
);

final _day = WorkoutDay(
  id: 'day-a',
  slot: 'A',
  label: 'Push',
  order: 0,
  exercises: [
    _exercise(0, 'Incline Barbell Bench Press', 'Chest', 60),
    _exercise(1, 'Seated Dumbbell Shoulder Press', 'Shoulders', 22.5),
    _exercise(2, 'Cable Triceps Pushdown', 'Triceps', 35),
  ],
);

final _plan = WorkoutPlan(
  id: 'plan-1',
  name: 'Push / Pull / Legs',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
  days: [_day],
);

void main() {
  runApp(const _Preview());
}

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      wallet: InMemoryWalletRepository(),
      expenseCategories: InMemoryCategoryRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      music: FakeMusicController(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: LiveSessionPage(day: _day, plan: _plan),
      ),
    );
  }
}
