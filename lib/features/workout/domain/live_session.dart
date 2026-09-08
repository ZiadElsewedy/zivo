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
    this.durationSource = DurationSource.measured,
    this.correctedDurationMinutes,
    this.voidReason,
    this.voidedAt,
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

  /// How [elapsed] was arrived at. Provenance, in the same spirit as
  /// [ADR-010](docs/DECISIONS/ADR-010-sleep-provenance.md): a duration that was
  /// reconstructed after the fact, or that is not knowable at all, must not be
  /// indistinguishable from one the app watched happen.
  final DurationSource durationSource;

  /// A duration the user set by hand, in whole minutes. When present it IS
  /// [elapsed]; [startedAt]/[completedAt] are still kept exactly as recorded,
  /// so the correction is an amendment on top of the record and never a
  /// rewrite of it.
  final int? correctedDurationMinutes;

  /// Why this session was withdrawn from the statistics, and when. Both null
  /// unless [status] is [SessionStatus.voided].
  final VoidReason? voidReason;
  final DateTime? voidedAt;

  // ---- Derived getters -----------------------------------------------------

  /// §3.2: a session's split IS its plan. [planId] already stores the split's
  /// id (a split is a `WorkoutPlan`), so this is a documented alias — no stored
  /// field, no serialization change — giving history/analysis code an explicit
  /// name for the split a session belongs to.
  String get splitId => planId;

  Iterable<LoggedSet> get allSets => exercises.expand((e) => e.sets);

  /// Whether this session logged at least one completed WORKING set — the bar
  /// for "you trained", used by the streak engine and by the staleness sweep
  /// to tell a real (if partial) workout from an empty shell.
  ///
  /// Working, not merely done: warming up and leaving is not training, which
  /// is the same line `analytics/plan_adherence.dart` already draws. Kept here
  /// rather than imported from the analytics engine so the domain's most basic
  /// question doesn't depend on its most elaborate file.
  bool get hasCompletedWorkingSet =>
      allSets.any((s) => s.done && s.type != SetType.warmup);

  /// The last moment there is any evidence training was happening — the
  /// newest [LoggedSet.resolvedAt] across every set. Null for a session whose
  /// sets carry no timestamps (nothing resolved yet, or a session logged
  /// before `resolvedAt` existed).
  ///
  /// This is the anchor for closing a session that was left open: the wall
  /// clock says the screen was up for nineteen hours, this says the last set
  /// was tapped at 7:14pm.
  DateTime? get lastActivityAt {
    DateTime? latest;
    for (final s in allSets) {
      final at = s.resolvedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }
  int get totalSets => exercises.fold(0, (sum, e) => sum + e.sets.length);
  int get completedSetCount => allSets.where((s) => s.done).length;

  /// Whether any still-pending set carries typed-but-unsubmitted actuals — a
  /// draft the user entered but never tapped Done on. A session in this
  /// state must never be silently discarded as "empty" on leave. A skipped
  /// set's leftover actuals are no longer a "draft" — they're already
  /// committed as skipped — so this deliberately checks [LoggedSet.pending],
  /// not just "not completed".
  bool get hasDraftActuals => allSets.any(
    (s) => s.pending && (s.actualReps != null || s.actualWeightKg != null),
  );

  /// 0..1 progress across all sets (0 when the session has no sets).
  double get progress => totalSets == 0 ? 0 : completedSetCount / totalSets;

  bool get allSetsDone => totalSets > 0 && completedSetCount == totalSets;
  bool get isComplete => status == SessionStatus.completed;
  bool get isPaused => pausedAt != null;
  bool get isVoided => status == SessionStatus.voided;

  /// Whether this session's record counts as training that happened —
  /// everything except a session that was quit or withdrawn. An `active`
  /// session counts: a workout half-logged and not yet finished still
  /// happened, and the streak must not pretend otherwise just because the
  /// user hasn't tapped Finish.
  bool get countsAsTraining =>
      status == SessionStatus.completed || status == SessionStatus.active;

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

  /// The set immediately before the current pointer, in the same
  /// exercise-then-set order [currentSet] walks — the most recently
  /// resolved set, and the target for the guided flow's "Back" control.
  /// Resolution only ever advances the pointer forward (markSetDone/
  /// markSetSkipped act on [currentSet] itself), so "immediately before
  /// current in list order" and "most recently resolved" are the same set
  /// as long as nothing has jumped around out of order. Null when there's
  /// nothing before it yet (nothing resolved). Works the same once every
  /// set is resolved and [currentSet] is null — it still finds the last one.
  (String exerciseId, LoggedSet set)? get previousResolvedSet {
    String? prevExerciseId;
    LoggedSet? prev;
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.pending) return prev == null ? null : (prevExerciseId!, prev);
        prevExerciseId = e.id;
        prev = s;
      }
    }
    return prev == null ? null : (prevExerciseId!, prev);
  }

  Duration get pausedAccum => Duration(milliseconds: pausedAccumMs);

  /// The session's final, official duration once it's finished — active
  /// training time, with every pause (accumulated by [complete] closing any
  /// still-open one first) excluded. Zero while still active.
  ///
  /// A [correctedDurationMinutes] the user set by hand wins outright. It is an
  /// amendment, not an edit: the raw [startedAt]/[completedAt] stay exactly as
  /// recorded underneath, and [durationSource] says which number this is.
  Duration get elapsed {
    final corrected = correctedDurationMinutes;
    if (corrected != null) return Duration(minutes: corrected);
    final raw = (completedAt ?? startedAt).difference(startedAt) - pausedAccum;
    // A clock moved backwards mid-session (manual change, or a network time
    // sync) can make this negative; a negative duration is never a fact.
    return raw.isNegative ? Duration.zero : raw;
  }

  /// Whether [elapsed] is a number the statistics may use.
  ///
  /// False when the duration is not knowable ([DurationSource.unknown] — a
  /// session closed with no per-set timestamps to close it at), when it is
  /// zero, or when it exceeds [maxSessionDuration]. Such a session keeps its
  /// place in history in full; it is only barred from *averages*, so one
  /// forgotten session can't quietly drag "how long a workout takes" toward a
  /// number that never happened.
  bool hasUsableDuration(Duration maxSessionDuration) {
    if (durationSource == DurationSource.unknown) return false;
    final d = elapsed;
    return d > Duration.zero && d <= maxSessionDuration;
  }

  /// Whether [elapsed] is longer than a session plausibly runs — the flag that
  /// puts a "needs a duration" affordance on the record.
  bool exceedsMaxDuration(Duration maxSessionDuration) =>
      elapsed > maxSessionDuration;

  /// Whether this still-[active] session has run past [maxSessionDuration]
  /// *and* gone quiet — the definition of "left open", and the only thing the
  /// staleness sweep acts on.
  ///
  /// Both halves are load-bearing. Running long alone is not stale: someone
  /// genuinely training at the three-hour mark is training, and closing their
  /// session out from under them would be the worst bug in this whole area.
  /// [kStaleInactivityGrace] with no set resolved is what separates the two —
  /// nobody logs nothing for half an hour and is still mid-workout.
  bool isStale({
    required DateTime now,
    required Duration maxSessionDuration,
  }) {
    if (status != SessionStatus.active) return false;
    if (activeElapsed(now: now) <= maxSessionDuration) return false;
    final since = now.difference(lastActivityAt ?? startedAt);
    return since > kStaleInactivityGrace;
  }

  /// The *live*, still-running active-time reading for an in-progress
  /// session — wall time since [startedAt], minus accumulated pauses, frozen
  /// at the moment a pause started if one is open right now. Callers pass
  /// `now`; this never reads the wall clock itself.
  Duration activeElapsed({required DateTime now}) {
    final raw = (pausedAt ?? now).difference(startedAt) - pausedAccum;
    return raw.isNegative ? Duration.zero : raw;
  }

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
  /// [now] is required, and is stamped onto the set as
  /// [LoggedSet.resolvedAt] — the session's duration is measured from these,
  /// so a resolution with no timestamp is a hole in the record.
  LiveSession markSetDone(
    String exerciseId,
    String setId, {
    required DateTime now,
    int? actualReps,
    double? actualWeightKg,
    double? rpe,
  }) => _mapSet(exerciseId, setId, (s) {
    final reps =
        actualReps ??
        (s.target.kind == RepTargetKind.fixed ? s.target.min : null);
    return s.copyWith(
      outcome: SetOutcome.completed,
      actualReps: reps,
      actualWeightKg: actualWeightKg ?? s.actualWeightKg ?? s.targetWeightKg,
      rpe: rpe ?? s.rpe,
      resolvedAt: now,
    );
  });

  /// Marks [setId] deliberately passed over — it advances the cursor exactly
  /// like [markSetDone] (see [currentSet]), but carries no logged volume:
  /// [completedSetCount]/history exclude it. Any actuals already typed for it
  /// (an abandoned draft) are preserved as-is, not cleared, so the end-of-
  /// workout review can still show what was entered.
  LiveSession markSetSkipped(
    String exerciseId,
    String setId, {
    required DateTime now,
  }) => _mapSet(
    exerciseId,
    setId,
    (s) => s.copyWith(outcome: SetOutcome.skipped, resolvedAt: now),
  );

  /// Un-does a completed or skipped set back to [SetOutcome.pending], making
  /// it the current set again — the Back/Undo primitive. Actuals are left
  /// untouched (Undo restores "current", it doesn't erase what was typed).
  /// [LoggedSet.resolvedAt] is cleared with the outcome — an un-done set was
  /// not resolved, and leaving its stamp behind would let an undone set go on
  /// defining when training stopped.
  LiveSession clearOutcome(String exerciseId, String setId) => _mapSet(
    exerciseId,
    setId,
    (s) => s.copyWith(outcome: SetOutcome.pending, resolvedAt: null),
  );

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
  }) => _mapSet(
    exerciseId,
    setId,
    (s) => LoggedSet(
      id: s.id,
      target: s.target,
      targetWeightKg: s.targetWeightKg,
      // Deliberately carried through untouched. Reviewing a set at the end of
      // a workout — or correcting one an hour later — is not performing it,
      // and re-stamping here would stretch the session's measured duration to
      // whenever the user happened to tidy up.
      resolvedAt: s.resolvedAt,
      actualReps: actualReps == _keep
          ? s.actualReps
          : (actualReps as num?)?.toInt(),
      actualWeightKg: actualWeightKg == _keep
          ? s.actualWeightKg
          : (actualWeightKg as num?)?.toDouble(),
      rpe: rpe == _keep ? s.rpe : (rpe as num?)?.toDouble(),
      type: type ?? s.type,
      outcome: outcome ?? s.outcome,
    ),
  );

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
    (e) => e.copyWith(
      sets: e.sets.where((s) => s.id != setId).toList(growable: false),
    ),
  );

  // ---- Exercise-level CRUD -------------------------------------------------

  LiveSession addExercise(SessionExercise exercise) =>
      copyWith(exercises: [...exercises, exercise]);

  LiveSession removeExercise(String exerciseId) => copyWith(
    exercises: exercises
        .where((e) => e.id != exerciseId)
        .toList(growable: false),
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

  /// FINISH NOW — ends a session that still has pending sets, at [now].
  ///
  /// The missing exit. Until this existed, a workout cut short had exactly two
  /// endings: leave it (it stays `active` forever, contributes nothing, and
  /// goes on offering itself as "resume" in place of the day that is actually
  /// due) or discard it (everything logged is gone). Neither is "I did four of
  /// six exercises and went home", which is a normal thing to do.
  ///
  /// **Nothing is invented.** Pending sets stay pending — they are not marked
  /// done and not marked skipped, and they carry no actuals, so
  /// [completedSetCount], `toWorkoutLog`, volume, PRs and every analytics path
  /// (all of which count only `done` sets) see exactly what the user entered
  /// and nothing more. The only thing this writes is the ending.
  ///
  /// [now] rather than [lastActivityAt] on purpose: this is a deliberate tap
  /// by someone standing in the gym, so the wall clock is the truth. The
  /// last-activity anchor is for [autoClose], where nobody is there to ask.
  LiveSession finishEarly({required DateTime now}) {
    if (status != SessionStatus.active) return this;
    final closed = isPaused ? resume(now: now) : this;
    return closed.copyWith(
      status: SessionStatus.completed,
      completedAt: now,
      durationSource: DurationSource.measured,
    );
  }

  /// Closes a session that was left open, at the last moment there is evidence
  /// anyone was training.
  ///
  /// This is the answer to the session that stays "running" from 6pm Tuesday
  /// to noon Wednesday. It does **not** cap the duration at some maximum —
  /// a capped number is a fabricated one wearing a measured number's clothes.
  /// It ends the session at [lastActivityAt], which is not a guess: it is when
  /// the user last tapped Done or Skip. A workout whose last set landed at
  /// 7:14pm gets its real 62 minutes, not three hours and not seventeen.
  ///
  /// When there is no such evidence — every set pending, or a session logged
  /// before per-set timestamps existed — the duration is genuinely unknowable,
  /// and it says so ([DurationSource.unknown]) rather than inventing one. Such
  /// a session keeps everything it logged, still counts as a day trained, and
  /// is simply left out of the duration averages until the user corrects it.
  ///
  /// Sets are never touched, in either branch.
  LiveSession autoClose({required DateTime now}) {
    if (status != SessionStatus.active) return this;
    final endedAt = lastActivityAt;
    return copyWith(
      status: SessionStatus.completed,
      completedAt: endedAt ?? startedAt,
      durationSource: endedAt == null
          ? DurationSource.unknown
          : DurationSource.autoClosed,
      // An open pause can only have begun AFTER the last set was resolved (a
      // set cannot be logged while paused), so it lies entirely outside
      // [startedAt, endedAt] and folding it in would subtract time that was
      // never counted in the first place. Dropped, not accumulated.
      pausedAt: null,
    );
  }

  /// Replaces the duration with one the user set, in whole minutes.
  ///
  /// The raw timestamps are untouched — this is an amendment on top of the
  /// record, marked [DurationSource.userCorrected] so the UI can say so.
  /// Passing null removes the correction and falls back to the measurement.
  /// **Sets, weights and outcomes are structurally out of reach here**: a
  /// duration lives on the session, performance lives under [exercises], and
  /// correcting one can never touch the other.
  LiveSession correctDuration(int? minutes) {
    if (minutes != null && minutes < 0) return this;
    return copyWith(
      correctedDurationMinutes: minutes,
      durationSource: minutes == null
          ? (completedAt == null
                ? DurationSource.unknown
                : DurationSource.measured)
          : DurationSource.userCorrected,
    );
  }

  /// VOID — withdraws a finished session from the statistics, keeping the
  /// record.
  ///
  /// The replacement for deleting a session you don't like the look of. A
  /// voided session still exists, still shows in History, and still says what
  /// was lifted; it is simply excluded from every average, streak and
  /// analysis. That asymmetry is the point: obviously-wrong data can be
  /// corrected, but history cannot be curated.
  LiveSession voidSession({required VoidReason reason, required DateTime now}) {
    if (status == SessionStatus.voided) return this;
    return copyWith(
      status: SessionStatus.voided,
      voidReason: reason,
      voidedAt: now,
    );
  }

  /// Undoes [voidSession], putting the session back into the statistics.
  LiveSession unvoid() {
    if (status != SessionStatus.voided) return this;
    return copyWith(
      status: SessionStatus.completed,
      voidReason: null,
      voidedAt: null,
    );
  }

  /// Undoes [complete] — back to active, [completedAt] cleared. A no-op
  /// unless the session is actually complete. Used to walk back an
  /// accidental Done/Skip that turned out to be the last pending set.
  LiveSession reopen() {
    if (status != SessionStatus.completed) return this;
    return copyWith(status: SessionStatus.active, completedAt: null);
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
    return copyWith(
      pausedAt: null,
      pausedAccumMs: pausedAccumMs + (addedMs < 0 ? 0 : addedMs),
    );
  }

  // ---- Internals -----------------------------------------------------------

  LiveSession _mapExercise(
    String exerciseId,
    SessionExercise Function(SessionExercise) fn,
  ) => copyWith(
    exercises: [for (final e in exercises) e.id == exerciseId ? fn(e) : e],
  );

  LiveSession _mapSet(
    String exerciseId,
    String setId,
    LoggedSet Function(LoggedSet) fn,
  ) => _mapExercise(
    exerciseId,
    (e) =>
        e.copyWith(sets: [for (final s in e.sets) s.id == setId ? fn(s) : s]),
  );

  LiveSession copyWith({
    SessionStatus? status,
    List<SessionExercise>? exercises,
    Object? completedAt = _keep,
    Object? pausedAt = _keep,
    int? pausedAccumMs,
    DurationSource? durationSource,
    Object? correctedDurationMinutes = _keep,
    Object? voidReason = _keep,
    Object? voidedAt = _keep,
  }) => LiveSession(
    id: id,
    planId: planId,
    dayId: dayId,
    dayLabel: dayLabel,
    startedAt: startedAt,
    status: status ?? this.status,
    exercises: exercises ?? this.exercises,
    completedAt: completedAt == _keep
        ? this.completedAt
        : completedAt as DateTime?,
    pausedAt: pausedAt == _keep ? this.pausedAt : pausedAt as DateTime?,
    pausedAccumMs: pausedAccumMs ?? this.pausedAccumMs,
    durationSource: durationSource ?? this.durationSource,
    correctedDurationMinutes: correctedDurationMinutes == _keep
        ? this.correctedDurationMinutes
        : correctedDurationMinutes as int?,
    voidReason: voidReason == _keep ? this.voidReason : voidReason as VoidReason?,
    voidedAt: voidedAt == _keep ? this.voidedAt : voidedAt as DateTime?,
  );
}

const Object _keep = Object();

/// How long a session already past its maximum must go with nothing logged
/// before the sweep will close it. Guards the one case that matters: a real
/// workout genuinely running long must never be closed out from under someone
/// who is still lifting. Nobody logs nothing for half an hour mid-workout.
const Duration kStaleInactivityGrace = Duration(minutes: 30);

/// Where a session's [LiveSession.elapsed] came from.
///
/// Provenance rather than a single number, for the reason
/// [ADR-010](docs/DECISIONS/ADR-010-sleep-provenance.md) gives about sleep: a
/// duration the app watched happen, one reconstructed afterwards from the last
/// set, one a user typed, and one nobody can know are four different claims,
/// and collapsing them into one field forces a lie in at least one case.
enum DurationSource {
  /// The app was there for it: the session ended when it ended.
  measured,

  /// The session was left open and was closed at its last logged set. The
  /// number is real, but it was reconstructed after the fact.
  autoClosed,

  /// The user set it by hand.
  userCorrected,

  /// Left open with nothing to close it at — no per-set timestamps. Excluded
  /// from every average until corrected, never guessed at.
  unknown,
}

/// Parses a stored [DurationSource] name, defaulting to [DurationSource.measured]
/// — which is what every session written before this field existed was.
DurationSource durationSourceFromName(String? name) => DurationSource.values
    .firstWhere((s) => s.name == name, orElse: () => DurationSource.measured);
