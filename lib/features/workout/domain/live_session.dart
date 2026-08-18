import 'logged_set.dart';
import 'planned_exercise.dart';
import 'rep_target.dart';
import 'session_exercise.dart';
import 'session_status.dart';
import 'set_type.dart';
import 'workout_day.dart';

/// A live (or finished) training session — the editable record of one workout.
///
/// Unlike the earlier linear guided engine, this is a full CRUD model: sets and
/// exercises can be added, edited, reordered, and deleted at any time, and every
/// performed set keeps its actuals. It stays immutable — each operation returns a
/// NEW [LiveSession] — and never reads the wall clock (callers pass `now`), so it
/// is deterministic and testable. Ids for inserted sets/exercises are supplied by
/// the caller to keep the model pure.
///
/// The "current" set is derived (the first not-done set in order), so edits keep
/// the guided highlight consistent without a stored cursor that could dangle.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.planId,
    required this.dayId,
    required this.dayLabel,
    required this.startedAt,
    required this.status,
    required this.exercises,
    this.completedAt,
  });

  final String id;
  final String planId;
  final String dayId;
  final String dayLabel;
  final DateTime startedAt;
  final SessionStatus status;
  final List<SessionExercise> exercises;
  final DateTime? completedAt;

  // ---- Derived getters -----------------------------------------------------

  Iterable<LoggedSet> get allSets => exercises.expand((e) => e.sets);
  int get totalSets => exercises.fold(0, (sum, e) => sum + e.sets.length);
  int get completedSetCount => allSets.where((s) => s.done).length;

  /// 0..1 progress across all sets (0 when the session has no sets).
  double get progress => totalSets == 0 ? 0 : completedSetCount / totalSets;

  bool get allSetsDone => totalSets > 0 && completedSetCount == totalSets;
  bool get isComplete => status == SessionStatus.completed;

  /// The exercise holding the first not-done set — what the user is on now.
  SessionExercise? get currentExercise {
    for (final e in exercises) {
      if (e.sets.any((s) => !s.done)) return e;
    }
    return null;
  }

  /// The first not-done set in order — the current target.
  LoggedSet? get currentSet {
    for (final e in exercises) {
      for (final s in e.sets) {
        if (!s.done) return s;
      }
    }
    return null;
  }

  Duration get elapsed => (completedAt ?? startedAt).difference(startedAt);

  // ---- Construction --------------------------------------------------------

  /// Starts a session from a planned [day] — one [SessionExercise] per planned
  /// exercise, its sets seeded from the plan (targets carried, actuals empty).
  static LiveSession start(
    WorkoutDay day, {
    required String id,
    required String planId,
    required DateTime now,
  }) => LiveSession(
    id: id,
    planId: planId,
    dayId: day.id,
    dayLabel: day.label,
    startedAt: now,
    status: SessionStatus.active,
    completedAt: null,
    exercises: [for (final e in day.exercises) _exerciseFromPlan(e)],
  );

  static SessionExercise _exerciseFromPlan(PlannedExercise e) => SessionExercise(
    id: e.id,
    exerciseId: e.id,
    name: e.name,
    muscleGroup: e.muscleGroup,
    restSeconds: e.defaultRestSeconds,
    sets: [
      for (var i = 0; i < e.sets.length; i++)
        LoggedSet(
          id: '${e.id}-s$i',
          target: e.sets[i].repTarget,
          targetWeightKg: e.sets[i].targetWeightKg,
          type: e.sets[i].type,
        ),
    ],
  );

  // ---- Set-level CRUD ------------------------------------------------------

  /// Marks [setId] done, recording actuals. [actualReps] defaults to the target
  /// when null and the target is a fixed count; ranges/to-failure stay as given.
  LiveSession markSetDone(
    String exerciseId,
    String setId, {
    int? actualReps,
    double? actualWeightKg,
    double? rpe,
  }) => _mapSet(exerciseId, setId, (s) {
    final reps = actualReps ?? (s.target.kind == RepTargetKind.fixed ? s.target.min : null);
    return s.copyWith(
      done: true,
      actualReps: reps,
      actualWeightKg: actualWeightKg ?? s.actualWeightKg ?? s.targetWeightKg,
      rpe: rpe ?? s.rpe,
    );
  });

  /// Edits a set's fields in place. Pass an explicit `null` to clear a nullable
  /// (weight/reps/rpe); omit an argument to keep it.
  LiveSession updateSet(
    String exerciseId,
    String setId, {
    Object? actualReps = _keep,
    Object? actualWeightKg = _keep,
    Object? rpe = _keep,
    bool? done,
    SetType? type,
  }) => _mapSet(exerciseId, setId, (s) => LoggedSet(
    id: s.id,
    target: s.target,
    targetWeightKg: s.targetWeightKg,
    actualReps: actualReps == _keep ? s.actualReps : (actualReps as num?)?.toInt(),
    actualWeightKg:
        actualWeightKg == _keep ? s.actualWeightKg : (actualWeightKg as num?)?.toDouble(),
    rpe: rpe == _keep ? s.rpe : (rpe as num?)?.toDouble(),
    type: type ?? s.type,
    done: done ?? s.done,
  ));

  /// Appends a set to [exerciseId], inheriting the last set's target/type/rest
  /// as sensible defaults. [setId] is caller-supplied.
  LiveSession addSet(String exerciseId, {required String setId}) =>
      _mapExercise(exerciseId, (e) {
        final template = e.sets.isNotEmpty ? e.sets.last : null;
        return e.copyWith(
          sets: [
            ...e.sets,
            LoggedSet(
              id: setId,
              target: template?.target ?? const RepTarget.fixed(8),
              targetWeightKg: template?.targetWeightKg,
              type: template?.type ?? SetType.working,
            ),
          ],
        );
      });

  LiveSession removeSet(String exerciseId, String setId) => _mapExercise(
    exerciseId,
    (e) => e.copyWith(sets: e.sets.where((s) => s.id != setId).toList(growable: false)),
  );

  // ---- Exercise-level CRUD -------------------------------------------------

  LiveSession addExercise(SessionExercise exercise) =>
      copyWith(exercises: [...exercises, exercise]);

  LiveSession removeExercise(String exerciseId) => copyWith(
    exercises: exercises.where((e) => e.id != exerciseId).toList(growable: false),
  );

  /// Renames an exercise (e.g. a machine swap) while keeping its [exerciseId] so
  /// history and previous-weight stay continuous.
  LiveSession renameExercise(String exerciseId, String name) =>
      _mapExercise(exerciseId, (e) => e.copyWith(name: name));

  // ---- Session-level transitions -------------------------------------------

  LiveSession complete({required DateTime now}) {
    if (status != SessionStatus.active) return this;
    return copyWith(status: SessionStatus.completed, completedAt: now);
  }

  LiveSession abandon({required DateTime now}) {
    if (status != SessionStatus.active) return this;
    return copyWith(status: SessionStatus.abandoned, completedAt: now);
  }

  // ---- Internals -----------------------------------------------------------

  LiveSession _mapExercise(String exerciseId, SessionExercise Function(SessionExercise) fn) =>
      copyWith(
        exercises: [
          for (final e in exercises) e.id == exerciseId ? fn(e) : e,
        ],
      );

  LiveSession _mapSet(String exerciseId, String setId, LoggedSet Function(LoggedSet) fn) =>
      _mapExercise(exerciseId, (e) => e.copyWith(
        sets: [for (final s in e.sets) s.id == setId ? fn(s) : s],
      ));

  LiveSession copyWith({
    SessionStatus? status,
    List<SessionExercise>? exercises,
    Object? completedAt = _keep,
  }) => LiveSession(
    id: id,
    planId: planId,
    dayId: dayId,
    dayLabel: dayLabel,
    startedAt: startedAt,
    status: status ?? this.status,
    exercises: exercises ?? this.exercises,
    completedAt: completedAt == _keep ? this.completedAt : completedAt as DateTime?,
  );
}

const Object _keep = Object();
