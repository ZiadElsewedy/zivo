import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/presentation/pages/workout_stats_pages.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Regression coverage for the Sessions drill-down's accuracy fixes: the
/// subtitle now accounts for every listed row (not just completed ones), and
/// an in-progress session shows its LIVE elapsed time instead of `elapsed`,
/// which is ~0/negative until completion (it measures start→completedAt).
void main() {
  LiveSession session({
    required String id,
    required SessionStatus status,
    required DateTime startedAt,
    DateTime? completedAt,
  }) => LiveSession(
    id: id,
    planId: 'p1',
    dayId: 'a',
    dayLabel: 'Push',
    startedAt: startedAt,
    completedAt: completedAt,
    status: status,
    exercises: const [],
  );

  Widget wrap({required Widget child, required InMemoryWorkoutSessionRepository sessions}) {
    return AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: sessions,
      bodyWeight: InMemoryBodyWeightRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      child: MaterialApp(home: child),
    );
  }

  testWidgets('subtitle counts every row: completed plus not-completed', (tester) async {
    final sessions = InMemoryWorkoutSessionRepository();
    await sessions.saveSession(
      session(
        id: 's1',
        status: SessionStatus.completed,
        startedAt: DateTime.now().subtract(const Duration(hours: 2)),
        completedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    await sessions.saveSession(
      session(
        id: 's2',
        status: SessionStatus.abandoned,
        startedAt: DateTime.now().subtract(const Duration(hours: 5)),
        completedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 50)),
      ),
    );

    await tester.pumpWidget(wrap(child: const WorkoutSessionsPage(), sessions: sessions));
    await tester.pump();

    expect(find.textContaining('1 COMPLETED WORKOUT · 1 NOT COMPLETED'), findsOneWidget);
    expect(find.text('ENDED EARLY'), findsOneWidget);
  });

  testWidgets('an in-progress session renders its live elapsed time, not ~0m', (
    tester,
  ) async {
    final sessions = InMemoryWorkoutSessionRepository();
    // Started 20 minutes ago, still active. The old code rendered
    // `_durationLabel(session.elapsed)` here — elapsed is start→completedAt
    // minus pauses, and completedAt is null while active, so this read as
    // "20m" minus nothing only by accident of the fallback; with any pause
    // bookkeeping it could render "0m" or negative.
    await sessions.saveSession(
      session(id: 's1', status: SessionStatus.active, startedAt: DateTime.now().subtract(const Duration(minutes: 20))),
    );

    await tester.pumpWidget(wrap(child: const WorkoutSessionsPage(), sessions: sessions));
    await tester.pump();

    expect(find.textContaining('· 20m ·'), findsOneWidget);
    expect(find.text('IN PROGRESS'), findsOneWidget);
  });
}
