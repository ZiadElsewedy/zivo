import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/exercise_history.dart';
import '../../domain/live_session.dart';
import '../../domain/live_session_to_workout_log.dart';
import '../../domain/logged_set.dart';
import '../../domain/progression.dart';
import '../../domain/rep_target.dart';
import '../../domain/rest_policy.dart';
import '../../domain/session_exercise.dart';
import '../../domain/set_type.dart';
import '../../domain/warmup_policy.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_session_repository.dart';
import '../widgets/staggered_reveal.dart';

/// The premium guided workout player (M1b) — walks the user set-by-set through
/// the day's exercises around the editable [LiveSession] model (M1a),
/// autosaving through [WorkoutSessionRepository] as sets are logged.
///
/// Visual hierarchy is the approved one: Pulse green marks a completed set,
/// Ember marks the current set, warm gray marks the rest state, and a Pulse
/// "↑" delta calls out progression over the last time this exercise was
/// trained ([lastPerformanceFor]).
///
/// Unlike the retired P3a/P3b engine, [LiveSession.currentSet] is *derived*
/// (the first not-done set), so marking a set done already advances the
/// pointer — rest is purely a UI-side pause laid over the next set, not a
/// separate engine phase.
class LiveSessionPage extends StatefulWidget {
  const LiveSessionPage({
    required this.day,
    required this.plan,
    this.resume,
    DateTime Function()? now,
    super.key,
  }) : now = now ?? DateTime.now;

  /// The day to run (a snapshot embedded in the session).
  final WorkoutDay day;

  /// The active plan — needed to advance its cursor when the session finishes.
  final WorkoutPlan plan;

  /// A previously-saved active session to resume into, in place of starting a
  /// fresh one from [day]. Passed by the plan page once it has an active
  /// session for this plan/day (`WorkoutSessionRepository.activeSession`).
  final LiveSession? resume;

  /// The clock this session runs on — real wall time in production, injected
  /// in tests so the rest timer's elapsed-time math is deterministic.
  final DateTime Function() now;

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> with WidgetsBindingObserver {
  late LiveSession _session;

  final TextEditingController _reps = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  Timer? _restTimer;
  int? _restRemaining;
  int? _restTotalSeconds;

  /// Debounces the current set's typed-but-not-done actuals into an
  /// autosaved draft (see [_saveDraft]) — never lose data even if the app
  /// is killed before Done is tapped.
  Timer? _draftDebounce;

  /// The absolute wall-clock moment rest ends — the source of truth for
  /// [_restRemaining], recomputed on every tick and on app resume so a
  /// backgrounded/suspended timer can't leave the countdown stale. Null
  /// while paused (a rest in progress is frozen into [_pausedRestRemaining]
  /// instead) as well as whenever there's no rest running.
  DateTime? _restEndsAt;

  /// The rest time left over from an active countdown that got paused —
  /// restored (as a fresh [_restEndsAt]) on resume. Null unless a rest was
  /// actually running at the moment [_onPause] was tapped.
  Duration? _pausedRestRemaining;

  /// Ticks the "time in workout" label once a second — just a rebuild
  /// trigger; the displayed value itself is always read fresh from
  /// [LiveSession.activeElapsed]/[LiveSession.elapsed] in [build], so it
  /// can't drift from the session's own pause-aware model state. Not
  /// running while paused or once the session completes.
  Timer? _elapsedTimer;

  /// Whether the current set's actuals in [_reps]/[_weight] reflect real
  /// user input (or an already-saved draft) rather than just an untouched
  /// goal/ramp suggestion — [_saveDraft] must never write a suggestion the
  /// user never actually looked at into the session as if it were typed.
  /// Set by [_onActualChanged] and re-derived by [_prefillInputs] whenever
  /// the current set changes.
  bool _actualsTouched = false;

  bool _reposInitialized = false;
  late WorkoutSessionRepository _sessionsRepo;
  StreamSubscription<List<LiveSession>>? _pastSessionsSub;
  List<LiveSession> _pastSessions = const [];

  /// The very first real history snapshot arrives asynchronously (even the
  /// in-memory repo's stream yields nothing synchronously), so the initial
  /// [_prefillInputs] call in [initState] runs before [_pastSessions] is
  /// populated — the goal it seeds from can't yet see prior performance.
  /// Re-running it once, the moment real history lands, keeps the prefilled
  /// reps/weight in sync with what the Goal block ends up showing. Also the
  /// trigger for [_materializeWarmupsFromHistory] — see there for why warm-up
  /// ramps can't be seeded any earlier than this.
  bool _prefillRefreshedFromHistory = false;

  /// Guards [_onFinish]/[_onLeave]/[_onDiscard] against re-entrancy — all are
  /// async and otherwise callable again (double-tap, or Finish racing the
  /// close button) before the first call's writes/pop land.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session =
        widget.resume ??
        LiveSession.start(
          widget.day,
          id: widget.now().microsecondsSinceEpoch.toString(),
          planId: widget.plan.id,
          now: widget.now(),
        );
    if (_session.currentSet == null) {
      // Nothing to do (an empty day) — settle straight into the completed view.
      _session = _session.complete(now: widget.now());
    }
    if (!_session.isComplete && !_session.isPaused) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickElapsed());
    }
    _prefillInputs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reposInitialized) return;
    _reposInitialized = true;
    _sessionsRepo = AppScope.of(context).workoutSessions;
    _pastSessionsSub = _sessionsRepo.watchAll().listen((sessions) {
      if (!mounted) return;
      setState(() {
        _pastSessions = sessions.where((s) => s.id != _session.id).toList(growable: false);
      });
      if (!_prefillRefreshedFromHistory) {
        _prefillRefreshedFromHistory = true;
        _prefillInputs();
        _materializeWarmupsFromHistory();
      }
    });
    unawaited(_sessionsRepo.saveSession(_session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS suspends `Timer`s while backgrounded, so a plain tick-counter
    // would resume from wherever it froze — resync both timers from their
    // wall-clock sources of truth instead. Both no-op on their own if the
    // session is explicitly paused (`_restEndsAt` is null while paused, and
    // `_tickElapsed` bails on `_session.isPaused`), so backgrounding while
    // paused can't sneak the clock back to life.
    if (state == AppLifecycleState.resumed) {
      _tickRest();
      _tickElapsed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTimer?.cancel();
    _elapsedTimer?.cancel();
    _draftDebounce?.cancel();
    _pastSessionsSub?.cancel();
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ---- Input prefill -------------------------------------------------------

  /// Seeds the reps/weight inputs — preferring a typed-but-not-done draft
  /// (see [_saveDraft]) over any computed suggestion, so returning to a set
  /// shows what was actually typed, not a reset. A never-touched warm-up set
  /// seeds from the ramp's own prescription (no progression math applies to
  /// warm-ups); a never-touched working set seeds from the computed
  /// [ProgressionGoal] — the plan's own prescription when there's no history
  /// for this exact set, or the double-progression suggestion once there is.
  /// "AMRAP" (to-failure, no history) has no number to seed, so reps is left
  /// blank for the user.
  void _prefillInputs() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) {
      _reps.text = '';
      _weight.text = '';
      _actualsTouched = false;
      return;
    }
    if (set.actualReps != null || set.actualWeightKg != null) {
      _reps.text = set.actualReps?.toString() ?? '';
      _weight.text = set.actualWeightKg != null ? _trimWeight(set.actualWeightKg!) : '';
      // A real, already-saved draft — not just an untouched suggestion.
      _actualsTouched = true;
      return;
    }
    _actualsTouched = false;
    if (set.type == SetType.warmup) {
      _reps.text = set.target.min?.toString() ?? '';
      _weight.text = set.targetWeightKg != null ? _trimWeight(set.targetWeightKg!) : '';
      return;
    }
    final goal = computeGoal(
      target: set.target,
      targetWeightKg: set.targetWeightKg,
      previous: _previousSetFor(exercise, set),
      muscleGroup: exercise.muscleGroup,
    );
    _reps.text = goal.repsLabel == 'AMRAP' ? '' : goal.repsLabel;
    _weight.text = goal.weightKg != null ? _trimWeight(goal.weightKg!) : '';
  }

  /// Schedules [_saveDraft] ~450ms out, restarting the delay on every
  /// keystroke — cheap enough not to write on every character, but short
  /// enough that a kill mid-typing rarely loses more than a moment's input.
  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 450), _saveDraft);
  }

  /// Persists whatever's currently typed into the current set's actuals
  /// WITHOUT marking it done — the "never lose data" path. Called both from
  /// the debounce timer and synchronously from [_onLeave], so a leave right
  /// after typing (before the debounce would have fired) still flushes.
  void _saveDraft() {
    _draftDebounce?.cancel();
    if (!mounted || !_actualsTouched) return;
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    final reps = int.tryParse(_reps.text.trim());
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (reps == set.actualReps && weight == set.actualWeightKg) return;
    setState(() {
      _session = _session.updateSet(exercise.id, set.id, actualReps: reps, actualWeightKg: weight);
    });
    unawaited(_sessionsRepo.saveSession(_session));
  }

  /// Wired to both actual-value [_ActualField]s: keeps the live progression
  /// delta reactive to every keystroke, and schedules the debounced draft
  /// save that makes typed input survive a leave or app-kill.
  void _onActualChanged() {
    _actualsTouched = true;
    setState(() {});
    _scheduleDraftSave();
  }

  // ---- Previous performance --------------------------------------------------

  ExerciseHistory? _historyFor(SessionExercise exercise) =>
      lastPerformanceFor(exercise.exerciseId, _pastSessions);

  /// Index-aligned against [history]'s *working* sets only — warm-up ramp
  /// steps aren't comparable across sessions (their count can change with
  /// the working weight, see [warmupRampFor]), so raw position would
  /// misalign a working set's "last time" once the ramp's step count
  /// differs from last session's.
  LoggedSet? _previousSetFor(SessionExercise exercise, LoggedSet set) {
    if (set.type != SetType.working) return null;
    final history = _historyFor(exercise);
    if (history == null) return null;
    final workingHistory = history.sets.where((s) => s.type == SetType.working).toList(
      growable: false,
    );
    final index = workingSetIndexOf(exercise, set);
    if (index < 0 || index >= workingHistory.length) return null;
    return workingHistory[index];
  }

  // ---- Warm-up materialization ----------------------------------------------

  /// [LiveSession.start] seeds a warm-up ramp from the *plan's own*
  /// `targetWeightKg` — but that's null for virtually every real plan (both
  /// the ingested seed plan and the plan editor leave weight for the user to
  /// fill in-app; the working weight that actually matters lives in session
  /// history, via the same computed [ProgressionGoal] already shown on the
  /// Goal card). So the ramp has to be able to source from *that* weight
  /// too, once it's known — which, like [_prefillInputs]'s own history
  /// dependency, isn't until the first real snapshot lands from
  /// [_pastSessionsSub]. Backfills a ramp for every exercise that doesn't
  /// already have one (from the plan-weight path, or already persisted on a
  /// [resume]d session) and hasn't been started yet — an exercise with any
  /// done set is left alone entirely, never retro-fitted.
  void _materializeWarmupsFromHistory() {
    var changed = false;
    final updatedExercises = [
      for (final exercise in _session.exercises)
        _materializedExercise(exercise, markChanged: () => changed = true),
    ];
    if (!changed) return;
    setState(() {
      _session = _session.copyWith(exercises: updatedExercises);
    });
    _prefillInputs();
    unawaited(_sessionsRepo.saveSession(_session));
  }

  SessionExercise _materializedExercise(
    SessionExercise exercise, {
    required VoidCallback markChanged,
  }) {
    final alreadyHasWarmup = exercise.sets.any((s) => s.type == SetType.warmup);
    // "In progress" includes a typed-but-not-done draft (see [_saveDraft]),
    // not just a done set — retro-fitting a ramp in front of a set the user
    // already has real input on would silently bury that input behind new
    // warm-up steps, which is exactly the kind of surprise the never-lose-
    // data guarantee exists to prevent.
    final alreadyInProgress = exercise.sets.any(
      (s) => s.done || s.actualReps != null || s.actualWeightKg != null,
    );
    if (alreadyHasWarmup || alreadyInProgress) return exercise;

    LoggedSet? firstWorking;
    for (final s in exercise.sets) {
      if (s.type == SetType.working) {
        firstWorking = s;
        break;
      }
    }
    if (firstWorking == null) return exercise;

    // The exact same weight the Goal card will show once this set is
    // current — plan prescription if there's no history yet, otherwise the
    // double-progression suggestion.
    final goalWeight = computeGoal(
      target: firstWorking.target,
      targetWeightKg: firstWorking.targetWeightKg,
      previous: _previousSetFor(exercise, firstWorking),
      muscleGroup: exercise.muscleGroup,
    ).weightKg;
    if (goalWeight == null) return exercise; // nothing to ramp toward

    final ramp = warmupRampFor(workingWeightKg: goalWeight, muscleGroup: exercise.muscleGroup);
    if (ramp.isEmpty) return exercise;

    markChanged();
    return exercise.copyWith(
      sets: [
        for (var i = 0; i < ramp.length; i++)
          LoggedSet(
            id: '${exercise.id}-w$i',
            target: RepTarget.fixed(ramp[i].reps),
            targetWeightKg: ramp[i].weightKg,
            type: SetType.warmup,
          ),
        ...exercise.sets,
      ],
    );
  }

  // ---- Transitions -----------------------------------------------------------

  void _onSetDone() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    final reps = int.tryParse(_reps.text.trim());
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    setState(() {
      _session = _session.markSetDone(
        exercise.id,
        set.id,
        actualReps: reps,
        actualWeightKg: weight,
      );
      if (_session.currentSet == null) {
        _session = _session.complete(now: widget.now());
      }
    });
    unawaited(_sessionsRepo.saveSession(_session));
    _prefillInputs();
    if (_session.isComplete) {
      _restTimer?.cancel();
      _restTotalSeconds = null;
      _restEndsAt = null;
      _elapsedTimer?.cancel();
      setState(() => _restRemaining = null);
      return;
    }
    _startRest(
      set.type == SetType.warmup
          ? _warmupRestSeconds
          : smartRestSeconds(
              repTargetMin: set.target.min ?? 1,
              muscleGroup: exercise.muscleGroup,
              workingSetIndex: workingSetIndexOf(exercise, set),
            ),
    );
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    if (seconds <= 0) {
      setState(() {
        _restRemaining = null;
        _restTotalSeconds = null;
        _restEndsAt = null;
      });
      return;
    }
    _restTotalSeconds = seconds;
    _restEndsAt = widget.now().add(Duration(seconds: seconds));
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickRest());
  }

  /// Recomputes [_restRemaining] from [_restEndsAt] against the current wall
  /// clock — called on every timer tick and on app resume, so a `Timer` the
  /// OS suspended while backgrounded snaps back to the real remaining time
  /// instead of resuming from wherever it froze. A no-op while paused —
  /// `_restEndsAt` is null then (frozen into [_pausedRestRemaining] instead).
  void _tickRest() {
    final endsAt = _restEndsAt;
    if (endsAt == null) return;
    final remaining = _ceilSeconds(endsAt.difference(widget.now()));
    if (remaining <= 0) {
      _endRest();
    } else if (mounted) {
      setState(() => _restRemaining = remaining);
    }
  }

  void _endRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restTotalSeconds = null;
    _restEndsAt = null;
    if (mounted) setState(() => _restRemaining = null);
  }

  /// Just a rebuild trigger — the "time in workout" value itself is always
  /// read fresh from [LiveSession.activeElapsed] in [build]. A no-op (and
  /// self-cancels) once the session completes or is paused, same wall-clock-
  /// survives-backgrounding approach as rest.
  void _tickElapsed() {
    if (!mounted || _session.isComplete || _session.isPaused) {
      _elapsedTimer?.cancel();
      return;
    }
    setState(() {});
  }

  void _adjustRest(int delta) {
    final endsAt = _restEndsAt;
    if (endsAt == null) return;
    final nextEndsAt = endsAt.add(Duration(seconds: delta));
    if (!nextEndsAt.isAfter(widget.now())) {
      _endRest();
      return;
    }
    final remaining = _ceilSeconds(nextEndsAt.difference(widget.now()));
    _restEndsAt = nextEndsAt;
    // Keep the ring sensible: grow the total if the adjustment pushed the
    // remaining time past what it was counting down from.
    if (_restTotalSeconds != null && remaining > _restTotalSeconds!) {
      _restTotalSeconds = remaining;
    }
    setState(() => _restRemaining = remaining);
  }

  /// Pauses the workout: stops the elapsed clock, and — if a rest was
  /// actively counting down — freezes its remaining time rather than losing
  /// it. Model state ([LiveSession.pause]), so it's saved and survives
  /// leave/resume.
  void _onPause() {
    final now = widget.now();
    final endsAt = _restEndsAt;
    setState(() {
      _session = _session.pause(now: now);
      if (endsAt != null) {
        final remaining = endsAt.difference(now);
        _pausedRestRemaining = remaining;
        _restTimer?.cancel();
        _restEndsAt = null;
        _restRemaining = _ceilSeconds(remaining);
      }
    });
    _elapsedTimer?.cancel();
    unawaited(_sessionsRepo.saveSession(_session));
  }

  /// Resumes from [_onPause]: restarts the elapsed clock, and — if a rest
  /// was frozen — restores it from exactly where it left off.
  void _onResume() {
    final now = widget.now();
    final pausedRemaining = _pausedRestRemaining;
    setState(() {
      _session = _session.resume(now: now);
      if (pausedRemaining != null) {
        _pausedRestRemaining = null;
        _restEndsAt = now.add(pausedRemaining);
        _restTimer?.cancel();
        _restTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickRest());
      }
    });
    unawaited(_sessionsRepo.saveSession(_session));
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickElapsed());
  }

  void _onTogglePause() => _session.isPaused ? _onResume() : _onPause();

  /// Fires the Firestore writes without waiting for them: `.set()`/`.delete()`
  /// commit to the local cache (and any listener) immediately, cache-first —
  /// but the returned Future only resolves once the server acknowledges it,
  /// so awaiting it before popping would hang this button while offline.
  /// Online, the write still lands the same way; this only changes when we
  /// stop waiting for confirmation we don't need for a safe local pop.
  void _onFinish() {
    if (_busy) return;
    setState(() => _busy = true);
    final workouts = AppScope.of(context).workouts;
    final plans = AppScope.of(context).workoutPlans;
    final sessions = _sessionsRepo;
    unawaited(workouts.add(_session.toWorkoutLog()));
    unawaited(plans.savePlan(widget.plan.advanceCursor()));
    unawaited(sessions.saveSession(_session));
    Navigator.of(context).pop();
  }

  /// LEAVE: the close (X) button and the system/edge-swipe back gesture. The
  /// session already autosaves as it's played, so leaving just pops — no
  /// confirmation, nothing deleted, the plan's cursor untouched. Flushes any
  /// pending debounced draft first, so a leave right after typing (before
  /// the debounce would have fired on its own) never loses it. The one
  /// exception: a session with zero logged sets AND no typed draft is
  /// indistinguishable from never having started one, so it's discarded
  /// silently rather than left behind as a "Resume" with nothing in it — a
  /// typed-but-not-done draft, though, must never be discarded as "empty".
  void _onLeave() {
    if (_busy) return;
    _saveDraft();
    setState(() => _busy = true);
    _restTimer?.cancel();
    if (_session.completedSetCount == 0 && !_session.hasDraftActuals) {
      unawaited(_sessionsRepo.deleteSession(_session.id));
    }
    Navigator.of(context).pop();
  }

  /// DISCARD: the explicit destructive action, reached via the top bar's
  /// trailing trash control — erases the autosaved session entirely and
  /// leaves the plan's cursor untouched.
  Future<void> _onDiscard() async {
    if (_busy) return;
    final sessions = _sessionsRepo;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Discard this workout?', style: AppText.cardTitle),
        content: Text(
          "You'll lose this session's progress and the plan won't advance.",
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep going', style: AppText.button.copyWith(color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Discard', style: AppText.button.copyWith(color: AppColors.flareText)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    _restTimer?.cancel();
    unawaited(sessions.deleteSession(_session.id));
    Navigator.of(context).pop();
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The system/edge-swipe back gesture leaves like the close (X) button —
      // non-destructive, since the session already autosaves as it's played.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.ground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptureTopBar(
                title: _dayTitle(widget.day),
                onClose: _onLeave,
                trailing: CaptureIconButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: _onDiscard,
                  semanticLabel: 'Discard workout',
                  iconColor: AppColors.flareText,
                ),
              ),
              _ProgressBar(value: _session.progress),
              _ElapsedLabel(
                elapsed: _session.isComplete
                    ? _session.elapsed
                    : _session.activeElapsed(now: widget.now()),
                isPaused: _session.isPaused,
                onTogglePause: _session.isComplete ? null : _onTogglePause,
              ),
              Expanded(
                // Paused freezes the rest/elapsed clocks (model state), but a
                // paused session is still visually "on hold" — dim the phase
                // content and block its taps, no animation (kept minimal;
                // prominence here is about info hierarchy, not motion).
                child: IgnorePointer(
                  ignoring: _session.isPaused,
                  child: Opacity(
                    opacity: _session.isPaused ? 0.35 : 1,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(_phaseKey), child: _buildPhase()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _phaseKey {
    if (_session.isComplete) return 'completed';
    if (_restRemaining != null) return 'resting';
    return 'running:${_session.currentSet?.id}';
  }

  Widget _buildPhase() {
    if (_session.isComplete) return _buildCompleted();
    if (_restRemaining != null) return _buildResting();
    return _buildRunning();
  }

  Widget _buildRunning() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) {
      return const Center(child: Text('Nothing to do.'));
    }
    if (set.type == SetType.warmup) return _buildWarmupRunning(exercise, set);

    final target = set.target;
    final targetText = target.kind == RepTargetKind.toFailure
        ? null
        : '${repTargetLabel(target)} reps';
    final previousSet = _previousSetFor(exercise, set);
    final lastTimeLabel = _formatLastTime(previousSet);
    final goal = computeGoal(
      target: target,
      targetWeightKg: set.targetWeightKg,
      previous: previousSet,
      muscleGroup: exercise.muscleGroup,
    );
    // Working-only position — warm-up ramp steps (if any) sit before this
    // in `exercise.sets` but aren't part of the numbered working sequence.
    final workingSetCount = exercise.sets.where((s) => s.type == SetType.working).length;
    final workingIndex = workingSetIndexOf(exercise, set);

    return ListView(
      key: const ValueKey('running-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.m,
        AppSpacing.l,
        AppSpacing.l,
      ),
      children: [
        // Exercise header — consolidated: the name is the hero title, the
        // muscle group a quiet pill beside it. No standalone "Target: X"
        // line (that's now context inside the Goal card) and no separate
        // "SET N OF M" eyebrow (the chip row below is the one set-position
        // indicator).
        StaggeredReveal(index: 0, child: _exerciseHeader(exercise)),
        const SizedBox(height: AppSpacing.base),
        StaggeredReveal(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set ${workingIndex + 1} of $workingSetCount',
                style: AppText.meta.copyWith(color: AppColors.ink3),
              ),
              const SizedBox(height: AppSpacing.s),
              _SetChipRow(exercise: exercise, currentSetId: set.id),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        // The hero: a lifted card carrying the computed goal, the point of
        // this whole screen — everything above just orients the user to it.
        StaggeredReveal(
          index: 2,
          child: _GoalBlock(lastTimeLabel: lastTimeLabel, goal: goal, targetText: targetText),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ActualField(label: 'Reps', controller: _reps, onChanged: _onActualChanged),
                  const SizedBox(width: AppSpacing.m),
                  _ActualField(
                    label: 'Weight (kg)',
                    controller: _weight,
                    hint: '—',
                    onChanged: _onActualChanged,
                  ),
                ],
              ),
              _ProgressionDelta(previousSet: previousSet, weightController: _weight),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 4,
          child: PillButton(
            label: 'Done',
            icon: Icons.check_rounded,
            enabled: true,
            onTap: _onSetDone,
          ),
        ),
      ],
    );
  }

  /// The running screen's warm-up treatment: no Goal card (no progression
  /// math applies to a ramp step) and no "Set N of M" (that counter is
  /// working-sets-only) — a "WARM-UP" eyebrow plus the ramp's own
  /// weight/reps prescription stand in for both.
  Widget _buildWarmupRunning(SessionExercise exercise, LoggedSet set) {
    return ListView(
      key: const ValueKey('running-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.m,
        AppSpacing.l,
        AppSpacing.l,
      ),
      children: [
        StaggeredReveal(index: 0, child: _exerciseHeader(exercise)),
        const SizedBox(height: AppSpacing.base),
        StaggeredReveal(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Warm-up', style: AppText.meta.copyWith(color: AppColors.emberText)),
              const SizedBox(height: AppSpacing.s),
              _SetChipRow(exercise: exercise, currentSetId: set.id),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 2,
          child: _WarmupBlock(weightKg: set.targetWeightKg, reps: set.target.min),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 3,
          child: Row(
            children: [
              _ActualField(label: 'Reps', controller: _reps, onChanged: _onActualChanged),
              const SizedBox(width: AppSpacing.m),
              _ActualField(
                label: 'Weight (kg)',
                controller: _weight,
                hint: '—',
                onChanged: _onActualChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 4,
          child: PillButton(
            label: 'Done',
            icon: Icons.check_rounded,
            enabled: true,
            onTap: _onSetDone,
          ),
        ),
      ],
    );
  }

  Widget _exerciseHeader(SessionExercise exercise) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(exercise.name, style: AppText.cardTitle.copyWith(fontSize: 30)),
      if (exercise.muscleGroup != null) ...[
        const SizedBox(height: AppSpacing.s),
        _MuscleGroupPill(label: exercise.muscleGroup!),
      ],
    ],
  );

  Widget _buildResting() {
    final nextLabel = _nextUpLabel();
    return Padding(
      key: const ValueKey('resting'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(child: _Eyebrow('Rest', color: AppColors.ink3)),
          const SizedBox(height: 18),
          Center(
            child: _RestRing(
              remaining: _restRemaining ?? 0,
              total: _restTotalSeconds ?? 1,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text('Next: $nextLabel', style: AppText.rowTitle.copyWith(color: AppColors.ink2)),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _RestAdjustButton(label: '-15s', onTap: () => _adjustRest(-15))),
              const SizedBox(width: 12),
              Expanded(child: _RestAdjustButton(label: '+15s', onTap: () => _adjustRest(15))),
            ],
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Skip rest',
            icon: Icons.skip_next_rounded,
            color: AppColors.pulseText,
            enabled: true,
            onTap: _endRest,
          ),
        ],
      ),
    );
  }

  Widget _buildCompleted() {
    final elapsed = _session.elapsed;
    final loggedExercises = _session.exercises.where((e) => e.doneSetCount > 0).toList();
    return ListView(
      key: const ValueKey('completed-list'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Center(child: _Eyebrow('Workout complete', color: AppColors.pulseText)),
        const SizedBox(height: 14),
        Center(
          child: _PopIn(
            child: Icon(Icons.check_circle_rounded, size: 56, color: AppColors.pulse),
          ),
        ),
        const SizedBox(height: 16),
        Text(widget.day.label, style: AppText.cardTitle.copyWith(fontSize: 24)),
        const SizedBox(height: 6),
        Text(
          '${_session.completedSetCount} of ${_session.totalSets} sets · ${elapsed.inMinutes} min',
          style: AppText.meta.copyWith(color: AppColors.pulseText),
        ),
        const SizedBox(height: 18),
        for (final (i, exercise) in loggedExercises.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: StaggeredReveal(
              index: i,
              child: Text(
                exercise.topWeightKg != null
                    ? '${exercise.name} · ${exercise.doneSetCount} sets · '
                          'top ${_trimWeight(exercise.topWeightKg!)}kg'
                    : '${exercise.name} · ${exercise.doneSetCount} sets',
                style: AppText.body.copyWith(fontSize: 15, color: AppColors.ink2),
              ),
            ),
          ),
        const SizedBox(height: 26),
        StaggeredReveal(
          index: loggedExercises.length,
          child: PillButton(
            label: 'Finish',
            icon: Icons.check_rounded,
            color: AppColors.pulseText,
            enabled: !_busy,
            onTap: _onFinish,
          ),
        ),
      ],
    );
  }

  /// What the user will do when the current rest ends — the (already
  /// advanced) current set/exercise, or Finish if the session is complete.
  String _nextUpLabel() {
    if (_session.isComplete) return 'Finish';
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return 'Finish';
    if (set.type == SetType.warmup) return 'Warm-up · ${exercise.name}';
    final workingIndex = workingSetIndexOf(exercise, set);
    return 'Set ${workingIndex + 1} · ${exercise.name}';
  }
}

// ---- Formatting -------------------------------------------------------------

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "Day A · Push".
String _dayTitle(WorkoutDay day) => 'Day ${day.slot} · ${day.label}';

/// "4:05" under an hour, "1:04:05" past one — the "time in workout" label.
String _formatElapsed(Duration d) {
  final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// "60kg × 8" — omits either half when unset; "First time" when there's no
/// previous performance to show at all (never trained, or never logged).
String _formatLastTime(LoggedSet? previous) {
  final parts = <String>[
    if (previous?.actualWeightKg != null) '${_trimWeight(previous!.actualWeightKg!)}kg',
    if (previous?.actualReps != null) '× ${previous!.actualReps}',
  ];
  return parts.isEmpty ? 'First time' : parts.join(' ');
}

/// Whole seconds remaining until [d] elapses, rounded up so a countdown
/// never flashes "0" a moment before it's actually over; clamped at 0 for an
/// already-elapsed duration.
int _ceilSeconds(Duration d) => d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();

/// A brief breather between warm-up ramp steps — deliberately far short of
/// [smartRestSeconds]'s full working-set rest window, since a ramp step
/// isn't taxing recovery the way a working set is.
const int _warmupRestSeconds = 20;

// ---- Small building blocks ----------------------------------------------

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          builder: (context, animatedValue, _) => LinearProgressIndicator(
            value: animatedValue,
            minHeight: 5,
            backgroundColor: AppColors.hairline,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.pulse),
          ),
        ),
      ),
    );
  }
}

/// The "time in workout" label — a small, tasteful clock + mm:ss just under
/// the progress bar, visible in every phase while the session is active and
/// frozen once it completes. Deliberately subtle; folded into the fuller
/// redesign later.
class _ElapsedLabel extends StatelessWidget {
  const _ElapsedLabel({required this.elapsed, required this.isPaused, required this.onTogglePause});

  final Duration elapsed;
  final bool isPaused;

  /// Null hides the pause/resume control entirely (once the session is
  /// complete — nothing left to pause).
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 13, color: AppColors.ink3),
          const SizedBox(width: 5),
          Text(
            _formatElapsed(elapsed),
            key: const Key('elapsed-timer'),
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          if (isPaused) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'PAUSED',
                key: const Key('paused-badge'),
                style: AppText.meta.copyWith(
                  color: AppColors.ink2,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (onTogglePause != null)
            InkWell(
              key: const Key('pause-toggle'),
              onTap: onTogglePause,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 16,
                      color: isPaused ? AppColors.pulseText : AppColors.ink3,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPaused ? 'Resume' : 'Pause',
                      style: AppText.meta.copyWith(
                        color: isPaused ? AppColors.pulseText : AppColors.ink3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Last-time + Goal card — the point of the running phase per the
/// "genuinely smarter" pass: a lifted card (the same `AppRadius.card` +
/// `AppShadows.card` language every other premium surface in the app uses)
/// so Goal reads as the dominant, hero element through hierarchy — biggest,
/// boldest, on its own tinted surface — not through any new motion. "Last
/// time" is a quiet supporting line, and the plan's own rep target sits
/// underneath as quieter context still. No animation beyond the shared
/// entrance stagger.
class _GoalBlock extends StatelessWidget {
  const _GoalBlock({required this.lastTimeLabel, required this.goal, this.targetText});

  final String lastTimeLabel;
  final ProgressionGoal goal;
  final String? targetText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.pulseWash,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 14, color: AppColors.pulseText),
              const SizedBox(width: 6),
              Text(
                'GOAL',
                style: AppText.meta.copyWith(
                  color: AppColors.pulseText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            goal.label,
            key: const Key('goal-label'),
            style: AppText.cardTitle.copyWith(
              fontSize: 32,
              color: AppColors.pulseText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            'Last time: $lastTimeLabel',
            key: const Key('last-time-label'),
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          if (targetText != null) ...[
            const SizedBox(height: 2),
            Text(
              'Target: $targetText',
              style: AppText.meta.copyWith(color: AppColors.ink3, fontWeight: FontWeight.w400),
            ),
          ],
        ],
      ),
    );
  }
}

/// The running screen's warm-up treatment, standing in for the Goal card
/// while the current set is an auto-generated ramp step — no progression
/// math applies here, just the ramp's own prescribed weight/reps ([weightKg]/
/// [reps]), in the same amber/ember hue as the current-set chip elsewhere on
/// this screen.
class _WarmupBlock extends StatelessWidget {
  const _WarmupBlock({required this.weightKg, required this.reps});

  final double? weightKg;
  final int? reps;

  @override
  Widget build(BuildContext context) {
    final guidance = [
      if (weightKg != null) '${_trimWeight(weightKg!)}kg',
      if (reps != null) '× $reps',
    ].join(' ');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.emberWash,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.whatshot_rounded, size: 14, color: AppColors.emberText),
              const SizedBox(width: 6),
              Text(
                'WARM-UP',
                style: AppText.meta.copyWith(
                  color: AppColors.emberText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Warm-up: $guidance',
            key: const Key('warmup-guidance'),
            style: AppText.cardTitle.copyWith(
              fontSize: 28,
              color: AppColors.emberText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet pill for the exercise's muscle group — beside the hero title
/// rather than a bare line under it.
class _MuscleGroupPill extends StatelessWidget {
  const _MuscleGroupPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(
        label,
        style: AppText.meta.copyWith(color: AppColors.ink2, fontSize: 12),
      ),
    );
  }
}

class _RestAdjustButton extends StatelessWidget {
  const _RestAdjustButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2, width: 1.4),
        ),
        child: Text(label, style: AppText.button.copyWith(fontSize: 15, color: AppColors.ink2)),
      ),
    );
  }
}

class _ActualField extends StatelessWidget {
  const _ActualField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.6),
          ),
          const SizedBox(height: AppSpacing.s),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            cursorColor: AppColors.ember,
            style: AppText.rowTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip + 4),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip + 4),
                borderSide: const BorderSide(color: AppColors.ember, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Pulse "↑" progression callout — shown once the entered weight beats
/// the last time this exact set (by index) was trained.
class _ProgressionDelta extends StatelessWidget {
  const _ProgressionDelta({required this.previousSet, required this.weightController});

  final LoggedSet? previousSet;
  final TextEditingController weightController;

  @override
  Widget build(BuildContext context) {
    final previousWeight = previousSet?.actualWeightKg;
    if (previousWeight == null) return const SizedBox.shrink();
    final entered = double.tryParse(weightController.text.trim().replaceAll(',', '.'));
    if (entered == null || entered <= previousWeight) return const SizedBox.shrink();
    final delta = entered - previousWeight;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.pulseText),
          const SizedBox(width: 2),
          Text(
            '+${_trimWeight(delta)}kg',
            style: AppText.meta.copyWith(color: AppColors.pulseText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

enum _ChipState { done, current, upcoming }

/// The current exercise's sets as a row of chips — Pulse green filled +
/// checkmark for done, a pulsing Ember disc for the current set, and a warm
/// gray outline for what's still upcoming.
class _SetChipRow extends StatelessWidget {
  const _SetChipRow({required this.exercise, required this.currentSetId});

  final SessionExercise exercise;
  final String currentSetId;

  @override
  Widget build(BuildContext context) {
    var workingNumber = 0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in exercise.sets)
          if (s.type == SetType.warmup)
            _WarmupChip(isCurrent: s.id == currentSetId, done: s.done)
          else
            _SetChip(
              number: ++workingNumber,
              state: s.done
                  ? _ChipState.done
                  : s.id == currentSetId
                  ? _ChipState.current
                  : _ChipState.upcoming,
            ),
      ],
    );
  }
}

/// A distinct hollow marker for a warm-up ramp step — deliberately not part
/// of the numbered working-set sequence ([_SetChip]), just a quiet signal
/// that a ramp step sits at this position.
class _WarmupChip extends StatelessWidget {
  const _WarmupChip({required this.isCurrent, required this.done});

  final bool isCurrent;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.emberWash : Colors.transparent,
        border: Border.all(color: AppColors.emberText, width: 1.4),
      ),
      child: const Icon(Icons.whatshot_rounded, size: 15, color: AppColors.emberText),
    );
    return isCurrent ? _PulsingGlow(color: AppColors.ember, child: dot) : dot;
  }
}

class _SetChip extends StatelessWidget {
  const _SetChip({required this.number, required this.state});

  final int number;
  final _ChipState state;

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          _ChipState.done => AppColors.pulse,
          _ChipState.current => AppColors.ember,
          _ChipState.upcoming => Colors.transparent,
        },
        border: state == _ChipState.upcoming
            ? Border.all(color: AppColors.hairline2, width: 1.4)
            : null,
      ),
      child: state == _ChipState.done
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : Text(
              '$number',
              style: AppText.meta.copyWith(
                color: state == _ChipState.current ? Colors.white : AppColors.ink3,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final popped = AnimatedScale(
      scale: state == _ChipState.current ? 1.1 : 1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: dot,
    );
    return state == _ChipState.current
        ? _PulsingGlow(color: AppColors.ember, child: popped)
        : popped;
  }
}

/// A gentle breathing glow — used behind the current-set indicator to draw
/// the eye without being distracting.
class _PulsingGlow extends StatefulWidget {
  const _PulsingGlow({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.22 + 0.18 * t),
                blurRadius: 10 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The rest countdown — a ring sweeping down over the rest window with the
/// remaining time centered inside, gently breathing. Warm gray/ink, per the
/// approved "rest" identity (Ember stays reserved for the current set, Pulse
/// for done).
class _RestRing extends StatelessWidget {
  const _RestRing({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    return _BreathingScale(
      child: SizedBox(
        width: 216,
        height: 216,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 950),
              curve: Curves.linear,
              builder: (context, value, _) => CustomPaint(
                size: const Size(216, 216),
                painter: _RestRingPainter(progress: value),
              ),
            ),
            Text(
              restLabel(remaining),
              style: AppText.greeting.copyWith(fontSize: 52, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestRingPainter extends CustomPainter {
  const _RestRingPainter({required this.progress});

  /// 1.0 = the full rest window remains, 0.0 = rest is over.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final track = Paint()
      ..color = AppColors.hairline2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final sweep = Paint()
      ..color = AppColors.ink2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _RestRingPainter oldDelegate) => oldDelegate.progress != progress;
}

/// A slow, subtle scale breathe — used behind the rest countdown so the warm
/// gray "rest" state still feels alive.
class _BreathingScale extends StatefulWidget {
  const _BreathingScale({required this.child});

  final Widget child;

  @override
  State<_BreathingScale> createState() => _BreathingScaleState();
}

class _BreathingScaleState extends State<_BreathingScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.98 + 0.04 * Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// A one-shot scale-in — used for the completion checkmark.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: child,
    );
  }
}
