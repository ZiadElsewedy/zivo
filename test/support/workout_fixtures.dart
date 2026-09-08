import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';

/// A session builder for the streak / duration suites.
///
/// Defaults to ONE completed working set, because that is the bar
/// `qualifiesForStreak` sets. A fixture written as `exercises: []` reads to a
/// human like a trained day and is not one — which is exactly the confusion
/// these tests exist to prevent, so the default here is a session that really
/// did something.
LiveSession session({
  required String id,
  required DateTime startedAt,
  Duration duration = const Duration(minutes: 50),
  SessionStatus status = SessionStatus.completed,
  String dayLabel = 'Push',
  String planId = 'p1',
  int workingSets = 1,
  int warmupSets = 0,
  int pendingSets = 0,
  int skippedSets = 0,
  bool stampResolvedAt = true,
  DurationSource durationSource = DurationSource.measured,
  int? correctedDurationMinutes,
  DateTime? completedAt,
  DateTime? lastSetAt,
  int pausedAccumMs = 0,
}) {
  final sets = <LoggedSet>[];
  var index = 0;
  final resolved = <int>[];

  LoggedSet build(String suffix, SetOutcome outcome, SetType type) {
    final i = index++;
    resolved.add(i);
    return LoggedSet(
      id: '$id-$suffix',
      target: const RepTarget.fixed(8),
      type: type,
      outcome: outcome,
      actualReps: outcome == SetOutcome.completed ? 8 : null,
      actualWeightKg: outcome == SetOutcome.completed ? 60 : null,
      resolvedAt: null,
    );
  }

  for (var i = 0; i < warmupSets; i++) {
    sets.add(build('w$i', SetOutcome.completed, SetType.warmup));
  }
  for (var i = 0; i < workingSets; i++) {
    sets.add(build('s$i', SetOutcome.completed, SetType.working));
  }
  for (var i = 0; i < skippedSets; i++) {
    sets.add(build('k$i', SetOutcome.skipped, SetType.working));
  }
  for (var i = 0; i < pendingSets; i++) {
    sets.add(
      LoggedSet(id: '$id-p$i', target: const RepTarget.fixed(8)),
    );
  }

  // Stamp the resolved sets so the LAST one lands on [lastSetAt] (or a few
  // minutes before the nominal end), which is what `lastActivityAt` reads.
  final resolvedCount = sets.where((s) => !s.pending).length;
  if (stampResolvedAt && resolvedCount > 0) {
    final end =
        lastSetAt ??
        (status == SessionStatus.active
            ? startedAt.add(duration)
            : (completedAt ?? startedAt.add(duration)));
    final span = end.difference(startedAt);
    var seen = 0;
    for (var i = 0; i < sets.length; i++) {
      if (sets[i].pending) continue;
      seen++;
      sets[i] = sets[i].copyWith(
        resolvedAt: startedAt.add(span * (seen / resolvedCount)),
      );
    }
  }

  return LiveSession(
    id: id,
    planId: planId,
    dayId: 'day-a',
    dayLabel: dayLabel,
    startedAt: startedAt,
    completedAt: status == SessionStatus.active
        ? null
        : (completedAt ?? startedAt.add(duration)),
    status: status,
    pausedAccumMs: pausedAccumMs,
    durationSource: durationSource,
    correctedDurationMinutes: correctedDurationMinutes,
    exercises: [
      SessionExercise(
        id: 'e1',
        exerciseId: 'bench',
        name: 'Bench Press',
        muscleGroup: 'Chest',
        restSeconds: 90,
        sets: sets,
      ),
    ],
  );
}
