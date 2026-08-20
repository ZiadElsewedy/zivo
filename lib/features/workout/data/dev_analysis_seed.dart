import '../domain/live_session.dart';
import '../domain/logged_set.dart';
import '../domain/planned_exercise.dart';
import '../domain/session_exercise.dart';
import '../domain/session_status.dart';
import '../domain/workout_day.dart';
import '../domain/workout_plan.dart';

/// Dev-only seed: a few completed sessions for the plan's first day, with a
/// deliberate mix of progressing/matched/down exercises, so the Analysis
/// page (Phase 2) has real week-over-week data to render on the simulator
/// without touching Firestore. Only ever wired into the in-memory session
/// repository (`USE_FIRESTORE=false` runs) — see `app.dart`; never reaches
/// real users.
List<LiveSession> devAnalysisSeedSessions(WorkoutPlan plan) {
  if (plan.days.isEmpty) return const [];
  final day = plan.days.first;
  final now = DateTime.now();
  final sessionDates = [
    now.subtract(const Duration(days: 21)),
    now.subtract(const Duration(days: 10)),
    now.subtract(const Duration(days: 2)),
  ];

  return [
    for (final (week, date) in sessionDates.indexed)
      _completedSession(day: day, planId: plan.id, week: week, date: date),
  ];
}

LiveSession _completedSession({
  required WorkoutDay day,
  required String planId,
  required int week,
  required DateTime date,
}) {
  final exercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));
  return LiveSession(
    id: 'dev-seed-${day.id}-w$week',
    planId: planId,
    dayId: day.id,
    dayLabel: day.label,
    startedAt: date,
    completedAt: date.add(const Duration(minutes: 52)),
    status: SessionStatus.completed,
    exercises: [for (final (i, e) in exercises.indexed) _sessionExercise(e, week: week, exerciseIndex: i)],
  );
}

/// Every 5th exercise holds flat (a "Matched" verdict), every 5th-plus-one
/// dips (a "Down" verdict), and the rest step up week over week
/// ("Progressing") — enough variety that the day-level rollup and every
/// verdict badge/trend chart have something real to show.
SessionExercise _sessionExercise(PlannedExercise e, {required int week, required int exerciseIndex}) {
  final pattern = exerciseIndex % 5;
  final baseWeight = 20.0 + exerciseIndex * 5;
  final baseReps = e.sets.isEmpty ? 8 : (e.sets.first.repTarget.min ?? 8);

  double weightFor(int w) => switch (pattern) {
    3 => baseWeight,
    4 => baseWeight - w * 1.25,
    _ => baseWeight + w * 2.5,
  };
  int repsFor(int w) => switch (pattern) {
    3 => baseReps,
    4 => (baseReps - w).clamp(4, 15),
    _ => (baseReps + (w == 0 ? 0 : 1)).clamp(4, 15),
  };

  return SessionExercise(
    id: e.id,
    exerciseId: e.id,
    name: e.name,
    muscleGroup: e.muscleGroup,
    restSeconds: e.defaultRestSeconds,
    sets: [
      for (var i = 0; i < e.sets.length; i++)
        LoggedSet(
          id: '${e.id}-s$i-w$week',
          target: e.sets[i].repTarget,
          targetWeightKg: e.sets[i].targetWeightKg,
          actualReps: repsFor(week),
          actualWeightKg: weightFor(week),
          done: true,
        ),
    ],
  );
}
