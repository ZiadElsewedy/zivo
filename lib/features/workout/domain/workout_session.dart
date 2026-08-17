import 'planned_exercise.dart';
import 'rep_target.dart';
import 'session_phase.dart';
import 'set_log.dart';
import 'workout_day.dart';
import 'workout_set.dart';

/// A live guided workout — an IMMUTABLE snapshot the UI renders and replaces via
/// pure transitions. Every transition returns a NEW [WorkoutSession]; nothing is
/// ever mutated in place, and no method reads the wall clock (callers pass `now`
/// wherever a timestamp is needed) so the engine is fully deterministic and
/// testable.
///
/// The session embeds a [WorkoutDay] snapshot so it is self-contained: indices
/// address positions in `day.exercises` and each exercise's `sets`, which the
/// plan's order-normalization keeps contiguous and 0-based. The rest belongs to
/// the set just finished, so [completeCurrentSet] enters [SessionPhase.resting]
/// WITHOUT advancing the pointer; [endRest] advances it.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.planId,
    required this.day,
    required this.startedAt,
    required this.phase,
    required this.currentExerciseIndex,
    required this.currentSetIndex,
    required this.logs,
    this.completedAt,
  });

  final String id;
  final String planId;
  final WorkoutDay day;
  final DateTime startedAt;
  final SessionPhase phase;
  final int currentExerciseIndex;
  final int currentSetIndex;
  final List<SetLog> logs;
  final DateTime? completedAt;

  // ---- Pure getters (no wall-clock reads, no mutation) ---------------------

  /// The exercise the pointer is on, or null if out of range (e.g. empty day).
  PlannedExercise? get currentExercise =>
      (currentExerciseIndex >= 0 && currentExerciseIndex < day.exercises.length)
      ? day.exercises[currentExerciseIndex]
      : null;

  /// The set the pointer is on, or null if out of range.
  PlannedSet? get currentSet {
    final exercise = currentExercise;
    if (exercise == null) return null;
    if (currentSetIndex < 0 || currentSetIndex >= exercise.sets.length) return null;
    return exercise.sets[currentSetIndex];
  }

  /// 1-based position of the current set within its exercise.
  int get currentSetNumber => currentSetIndex + 1;

  /// How many sets the current exercise has.
  int get exerciseSetCount => currentExercise?.sets.length ?? 0;

  /// The exercise after the current one, or null if this is the last.
  PlannedExercise? get nextExercise =>
      (currentExerciseIndex + 1 < day.exercises.length)
      ? day.exercises[currentExerciseIndex + 1]
      : null;

  /// Every planned set across the day — the progress-bar denominator.
  int get totalSets => day.exercises.fold(0, (sum, e) => sum + e.sets.length);

  /// How many sets have been completed — the progress-bar numerator.
  int get completedSetCount => logs.where((l) => l.done).length;

  /// The rest for the set the pointer is on. During [SessionPhase.resting] the
  /// pointer still sits on the just-completed set, so this is that set's rest.
  int get currentRestSeconds => currentSet?.restSeconds ?? 0;

  bool get isResting => phase == SessionPhase.resting;
  bool get isComplete => phase == SessionPhase.completed;

  // ---- Pure transitions (each returns a new WorkoutSession) ----------------

  /// Begins a session on [day], pointer at the first set, running, no logs.
  static WorkoutSession start(
    WorkoutDay day, {
    required String id,
    required String planId,
    required DateTime now,
  }) => WorkoutSession(
    id: id,
    planId: planId,
    day: day,
    startedAt: now,
    phase: SessionPhase.running,
    currentExerciseIndex: 0,
    currentSetIndex: 0,
    logs: const [],
  );

  /// Records the current set as done and moves to rest — or to [completed] when
  /// it was the final set of the final exercise (no rest after the last set).
  /// The pointer is NOT advanced here; the rest belongs to this set. A no-op
  /// unless [running] with a valid current set.
  ///
  /// [actualReps] defaults to the target when null and the target is a fixed
  /// count; for ranges and to-failure it stays null unless supplied.
  WorkoutSession completeCurrentSet({
    int? actualReps,
    double? actualWeightKg,
    required DateTime now,
  }) {
    if (phase != SessionPhase.running) return this;
    final exercise = currentExercise;
    final set = currentSet;
    if (exercise == null || set == null) return this;

    final resolvedReps =
        actualReps ?? (set.repTarget.kind == RepTargetKind.fixed ? set.repTarget.min : null);
    final log = SetLog(
      exerciseId: exercise.id,
      setOrder: set.order,
      target: set.repTarget,
      actualReps: resolvedReps,
      actualWeightKg: actualWeightKg,
      done: true,
    );
    final newLogs = [...logs, log];

    final isLastSet = currentSetIndex >= exercise.sets.length - 1;
    final isLastExercise = currentExerciseIndex >= day.exercises.length - 1;
    if (isLastSet && isLastExercise) {
      return copyWith(logs: newLogs, phase: SessionPhase.completed, completedAt: now);
    }
    return copyWith(logs: newLogs, phase: SessionPhase.resting);
  }

  /// Ends the rest and advances the pointer to the next set (or the next
  /// exercise's first set), returning to [running]. A no-op unless [resting].
  WorkoutSession endRest() {
    if (phase != SessionPhase.resting) return this;
    final exercise = currentExercise;
    if (exercise == null) return this;

    if (currentSetIndex + 1 < exercise.sets.length) {
      return copyWith(currentSetIndex: currentSetIndex + 1, phase: SessionPhase.running);
    }
    if (currentExerciseIndex + 1 < day.exercises.length) {
      return copyWith(
        currentExerciseIndex: currentExerciseIndex + 1,
        currentSetIndex: 0,
        phase: SessionPhase.running,
      );
    }
    // Nothing remains (unreachable via the normal flow, which never rests after
    // the final set) — settle into completed.
    return copyWith(phase: SessionPhase.completed, completedAt: completedAt ?? startedAt);
  }

  /// Skipping the rest is the same transition as ending it early.
  WorkoutSession skipRest() => endRest();

  /// Quits the session. A no-op once terminal ([completed]/[abandoned]).
  WorkoutSession abandon({required DateTime now}) {
    if (phase == SessionPhase.completed || phase == SessionPhase.abandoned) return this;
    return copyWith(phase: SessionPhase.abandoned, completedAt: now);
  }

  WorkoutSession copyWith({
    SessionPhase? phase,
    int? currentExerciseIndex,
    int? currentSetIndex,
    List<SetLog>? logs,
    DateTime? completedAt,
  }) => WorkoutSession(
    id: id,
    planId: planId,
    day: day,
    startedAt: startedAt,
    phase: phase ?? this.phase,
    currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
    currentSetIndex: currentSetIndex ?? this.currentSetIndex,
    logs: logs ?? this.logs,
    completedAt: completedAt ?? this.completedAt,
  );
}
