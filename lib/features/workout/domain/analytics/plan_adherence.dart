/// Plan-adherence analysis — "what is being skipped?" (product brief §3).
///
/// The hub engine ([analyzeTraining]) only knows what you DID; it can't see
/// what you were supposed to do and didn't. This joins the active plan against
/// your completed history to surface the movements the plan prescribes but you
/// keep passing over — the ones that never get trained, and the ones that have
/// gone quiet. Pure over `(plan, sessions, now)`; no clock, no repository.
///
/// The join key is the canonical exercise: [PlannedExercise.canonicalId] ==
/// [SessionExercise.exerciseId] (see `LiveSession.start`). So an exercise
/// that sits in two slots — Pec Deck on Push and on Chest & Back — is one
/// movement here, trained whenever either slot was. Callers pass sessions
/// already read through `ExerciseIdentityResolver.canonicalize`, and the same
/// resolver so a slot pointing at a merged-away id still lines up. A
/// session "trained" an exercise only when it logged a working set for it —
/// showing up to warm up and leaving is not adherence.
library;

import '../identity/exercise_identity_resolver.dart';
import '../live_session.dart';
import '../planned_exercise.dart';
import '../session_status.dart';
import '../workout_plan.dart';
import 'workout_analytics.dart';

/// A planned movement is flagged stale once this many days pass without a
/// working set — about two weeks, long enough that a normal rotation should
/// have come back around to it.
const int kStalePlannedExerciseDays = 14;

/// Why a planned exercise is being surfaced as neglected.
enum AdherenceReason {
  /// In the plan, but never once trained in completed history.
  neverTrained,

  /// Trained before, but not within [kStalePlannedExerciseDays].
  stale,
}

/// One planned movement the user is neglecting, with the evidence.
class NeglectedExercise {
  const NeglectedExercise({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.dayLabel,
    required this.reason,
    required this.appearances,
    required this.daysSinceLast,
  });

  final String exerciseId;
  final String name;
  final String? muscleGroup;

  /// The plan day this movement belongs to (first, if it appears on several).
  final String dayLabel;
  final AdherenceReason reason;

  /// How many completed sessions logged a working set for it.
  final int appearances;

  /// Days since the last working set (null when [reason] is [neverTrained]).
  final int? daysSinceLast;
}

/// The adherence picture for one plan.
class PlanAdherence {
  const PlanAdherence({
    required this.neglected,
    required this.plannedExerciseCount,
  });

  /// Movements to surface, most-neglected first (never-trained before stale,
  /// then longest-quiet first).
  final List<NeglectedExercise> neglected;

  /// Distinct movements the plan prescribes — the denominator for "3 of 12
  /// planned movements are being skipped".
  final int plannedExerciseCount;

  bool get isEmpty => neglected.isEmpty;
}

/// Builds the [PlanAdherence] for [plan] as of [now]. Returns an empty result
/// when there is no plan, no planned movement, or no completed history to
/// judge against (a plan you have never trained from is not yet "skipping"
/// anything — it just hasn't started).
PlanAdherence analyzePlanAdherence({
  required WorkoutPlan? plan,
  required List<LiveSession> sessions,
  required DateTime now,
  ExerciseIdentityResolver? resolver,
}) {
  final identity = resolver ?? ExerciseIdentityResolver.identity;
  String keyOf(PlannedExercise ex) => identity.canonicalIdOf(ex.canonicalId);
  if (plan == null || plan.days.isEmpty) {
    return const PlanAdherence(neglected: [], plannedExerciseCount: 0);
  }

  final completed = sessions
      .where((s) => s.status == SessionStatus.completed)
      .toList(growable: false);
  if (completed.isEmpty) {
    // No training yet — nothing is being skipped, the plan just hasn't begun.
    return PlanAdherence(
      neglected: const [],
      plannedExerciseCount: _plannedIds(plan, keyOf).length,
    );
  }

  // Most-recent working date + appearance count per canonical movement id.
  final lastTrained = <String, DateTime>{};
  final appearances = <String, int>{};
  for (final session in completed) {
    final at = session.completedAt ?? session.startedAt;
    final seen = <String>{};
    for (final ex in session.exercises) {
      if (!ex.sets.any(isWorkingSet)) continue;
      seen.add(ex.exerciseId);
    }
    for (final id in seen) {
      appearances[id] = (appearances[id] ?? 0) + 1;
      final prev = lastTrained[id];
      if (prev == null || at.isAfter(prev)) lastTrained[id] = at;
    }
  }

  // Walk the plan once, deduping a movement that appears on several days
  // (first day label wins).
  final planned = <String>{};
  final out = <NeglectedExercise>[];
  for (final day in plan.days) {
    for (final ex in day.exercises) {
      final key = keyOf(ex);
      if (!planned.add(key)) continue; // already handled on an earlier day
      final count = appearances[key] ?? 0;
      if (count == 0) {
        out.add(NeglectedExercise(
          exerciseId: key,
          name: ex.name,
          muscleGroup: ex.muscleGroup,
          dayLabel: day.label,
          reason: AdherenceReason.neverTrained,
          appearances: 0,
          daysSinceLast: null,
        ));
        continue;
      }
      final last = lastTrained[key]!;
      final days = _daysBetween(last, now);
      if (days >= kStalePlannedExerciseDays) {
        out.add(NeglectedExercise(
          exerciseId: key,
          name: ex.name,
          muscleGroup: ex.muscleGroup,
          dayLabel: day.label,
          reason: AdherenceReason.stale,
          appearances: count,
          daysSinceLast: days,
        ));
      }
    }
  }

  out.sort((a, b) {
    // Never-trained first; then longest-quiet first.
    if (a.reason != b.reason) {
      return a.reason == AdherenceReason.neverTrained ? -1 : 1;
    }
    return (b.daysSinceLast ?? 1 << 30).compareTo(a.daysSinceLast ?? 1 << 30);
  });

  return PlanAdherence(neglected: out, plannedExerciseCount: planned.length);
}

Set<String> _plannedIds(
  WorkoutPlan plan,
  String Function(PlannedExercise) keyOf,
) {
  final ids = <String>{};
  for (final day in plan.days) {
    for (final ex in day.exercises) {
      ids.add(keyOf(ex));
    }
  }
  return ids;
}

int _daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
