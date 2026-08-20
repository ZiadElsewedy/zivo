import 'logged_set.dart';
import 'planned_exercise.dart';
import 'rep_target.dart';
import 'session_exercise.dart';
import 'session_status.dart';
import 'set_outcome.dart';
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
    this.pausedAt,
    this.pausedAccumMs = 0,
  });

  final String id;
  final String planId;
  final String dayId;
  final String dayLabel;
  final DateTime startedAt;
  final SessionStatus status;
  final List<SessionExercise> exercises;
  final DateTime? completedAt;

  /// When the current pause started, if the session is paused right now —
  /// null otherwise. Model state (not UI state) so a pause survives leave/
  /// resume: it's persisted through the session repository like everything
  /// else here.
  final DateTime? pausedAt;

  /// Total time spent paused across every pause so far, in milliseconds
  /// (stored as an int for a trivial Firestore round-trip — no `Duration`
  /// codec needed). Does NOT include a currently-open pause; that's added in
  /// once [resume] closes it.
  final int pausedAccumMs;

  // ---- Derived getters -----------------------------------------------------

  /// §3.2: a session's split IS its plan. [planId] already stores the split's
  /// id (a split is a `WorkoutPlan`), so this is a documented alias — no stored
  /// field, no serialization change — giving history/analysis code an explicit
  /// name for the split a session belongs to.
  String get splitId => planId;

  Iterable<LoggedSet> get allSets => exercises.expand((e) => e.sets);
  int get totalSets => exercises.fold(0, (sum, e) => sum + e.sets.length);
  int get completedSetCount => allSets.where((s) => s.done).length;

  /// Whether any still-pending set carries typed-but-unsubmitted actuals — a
  /// draft the user entered but never tapped Done on. A session in this
  /// state must never be silently discarded as "empty" on leave. A skipped
  /// set's leftover actuals are no longer a "draft" — they're already
  /// committed as skipped — so this deliberately checks [LoggedSet.pending],
  /// not just "not completed".
  bool get hasDraftActuals =>
      allSets.any((s) => s.pending && (s.actualReps != null || s.actualWeightKg != null));

  /// 0..1 progress across all sets (0 when the session has no sets).
  double get progress => totalSets == 0 ? 0 : completedSetCount / totalSets;

  bool get allSetsDone => totalSets > 0 && completedSetCount == totalSets;
  bool get isComplete => status == SessionStatus.completed;
  bool get isPaused => pausedAt != null;

  /// The exercise holding the first still-pending set — what the user is on
  /// now. A skipped set is resolved, not current — this is what lets a skip
  /// advance the same way completing a set does.
  SessionExercise? get currentExercise {
    for (final e in exercises) {
      if (e.sets.any((s) => s.pending)) return e;
    }
    return null;
  }

  /// The first still-pending set in order — the current target.
  LoggedSet? get currentSet {
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.pending) return s;
      }
    }
    return null;
  }

  Duration get pausedAccum => Duration(milliseconds: pausedAccumMs);

  /// The session's final, official duration once it's [complete] — active
  /// training time, with every pause (accumulated by [complete] closing any
  /// still-open one first) excluded. Zero while still active.
  Duration get elapsed => (completedAt ?? startedAt).difference(startedAt) - pausedAccum;

  /// The *live*, still-running active-time reading for an in-progress
  /// session — wall time since [startedAt], minus accumulated pauses, frozen
  /// at the moment a pause started if one is open right now. Callers pass
  /// `now`; this never reads the wall clock itself.
  Duration activeElapsed({required DateTime now}) =>
      (pausedAt ?? now).difference(startedAt) - pausedAccum;

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

  static SessionExercise _exerciseFromPlan(PlannedExercise e) {
    return SessionExercise(
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
  }

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
      outcome: SetOutcome.completed,
      actualReps: reps,
      actualWeightKg: actualWeightKg ?? s.actualWeightKg ?? s.targetWeightKg,
      rpe: rpe ?? s.rpe,
    );
  });

  /// Marks [setId] deliberately passed over — it advances the cursor exactly
  /// like [markSetDone] (see [currentSet]), but carries no logged volume:
  /// [completedSetCount]/history exclude it. Any actuals already typed for it
  /// (an abandoned draft) are preserved as-is, not cleared, so the end-of-
  /// workout review can still show what was entered.
  LiveSession markSetSkipped(String exerciseId, String setId) =>
      _mapSet(exerciseId, setId, (s) => s.copyWith(outcome: SetOutcome.skipped));

  /// Un-does a completed or skipped set back to [SetOutcome.pending], making
  /// it the current set again — the Back/Undo primitive. Actuals are left
  /// untouched (Undo restores "current", it doesn't erase what was typed).
  LiveSession clearOutcome(String exerciseId, String setId) =>
      _mapSet(exerciseId, setId, (s) => s.copyWith(outcome: SetOutcome.pending));

  /// Edits a set's fields in place. Pass an explicit `null` to clear a nullable
  /// (weight/reps/rpe); omit an argument to keep it.
  LiveSession updateSet(
    String exerciseId,
    String setId, {
    Object? actualReps = _keep,
    Object? actualWeightKg = _keep,
    Object? rpe = _keep,
    SetOutcome? outcome,
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
    outcome: outcome ?? s.outcome,
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
    // Close any still-open pause first, so its time lands in `pausedAccum`
    // and `elapsed` (computed from it) excludes it — the logged duration is
    // active training time, not wall time.
    final closed = isPaused ? resume(now: now) : this;
    return closed.copyWith(status: SessionStatus.completed, completedAt: now);
  }

  LiveSession abandon({required DateTime now}) {
    if (status != SessionStatus.active) return this;
    return copyWith(status: SessionStatus.abandoned, completedAt: now);
  }

  /// Pauses the timer — a no-op if already paused or not active. Model
  /// state, so it's saved through the session repository and survives
  /// leave/resume.
  LiveSession pause({required DateTime now}) {
    if (isPaused || status != SessionStatus.active) return this;
    return copyWith(pausedAt: now);
  }

  /// Resumes from a pause, folding the just-closed pause's duration into
  /// [pausedAccum] — a no-op if not currently paused.
  LiveSession resume({required DateTime now}) {
    final at = pausedAt;
    if (at == null) return this;
    final addedMs = now.difference(at).inMilliseconds;
    return copyWith(pausedAt: null, pausedAccumMs: pausedAccumMs + (addedMs < 0 ? 0 : addedMs));
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
    Object? pausedAt = _keep,
    int? pausedAccumMs,
  }) => LiveSession(
    id: id,
    planId: planId,
    dayId: dayId,
    dayLabel: dayLabel,
    startedAt: startedAt,
    status: status ?? this.status,
    exercises: exercises ?? this.exercises,
    completedAt: completedAt == _keep ? this.completedAt : completedAt as DateTime?,
    pausedAt: pausedAt == _keep ? this.pausedAt : pausedAt as DateTime?,
    pausedAccumMs: pausedAccumMs ?? this.pausedAccumMs,
  );
}

const Object _keep = Object();
