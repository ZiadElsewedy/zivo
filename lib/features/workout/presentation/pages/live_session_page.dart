import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/exercise_history.dart';
import '../../domain/live_session.dart';
import '../../domain/live_session_to_workout_log.dart';
import '../../domain/logged_set.dart';
import '../../domain/progress_comparison.dart';
import '../../domain/progression.dart';
import '../../domain/rep_target.dart';
import '../../domain/rest_policy.dart';
import '../../domain/session_exercise.dart';
import '../../domain/set_type.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_session_repository.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/verdict_style.dart';

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

class _LiveSessionPageState extends State<LiveSessionPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late LiveSession _session;

  final TextEditingController _reps = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  /// Drives the premium rest countdown at frame rate (~60fps) rather than
  /// once a second — every tick just triggers a rebuild; the actual
  /// remaining time is always recomputed fresh from [_restEndsAt] against
  /// [widget.now], never accumulated from the ticker's own elapsed time, so
  /// it stays wall-clock-correct through pause/resume/adjust exactly like
  /// the old 1Hz timer did.
  Ticker? _restTicker;
  int? _restTotalSeconds;

  /// Drives the pre-workout warm-up countdown at the same per-frame rate as
  /// [_restTicker] — a distinct phase shown once, before the first set of a
  /// genuinely fresh session. This is the app's one warm-up: the old
  /// per-exercise ramp warm-up SETS have been retired (owner decision).
  Ticker? _warmupTicker;
  int? _warmupTotalSeconds;

  /// Debounces the current set's typed-but-not-done actuals into an
  /// autosaved draft (see [_saveDraft]) — never lose data even if the app
  /// is killed before Done is tapped.
  Timer? _draftDebounce;

  /// The absolute wall-clock moment rest ends — the single source of truth
  /// [_restRemaining] reads on every frame (and on app resume, so a
  /// backgrounded/suspended app snaps back to the real remaining time
  /// instead of resuming from wherever it froze). Null while paused (a rest
  /// in progress is frozen into [_pausedRestRemaining] instead) as well as
  /// whenever there's no rest running.
  DateTime? _restEndsAt;

  /// The rest time left over from an active countdown that got paused —
  /// restored (as a fresh [_restEndsAt]) on resume. Null unless a rest was
  /// actually running at the moment [_onPause] was tapped.
  Duration? _pausedRestRemaining;

  /// The [_restEndsAt] analog for the pre-workout warm-up phase — the
  /// absolute wall-clock moment it ends. Null once skipped/expired, and
  /// never re-armed after that (see [_phaseKey]/[initState]: it's a one-shot
  /// phase, not persisted, so leaving and resuming just lands on the first
  /// set rather than re-showing it).
  DateTime? _warmupEndsAt;

  /// The [_pausedRestRemaining] analog for the warm-up phase.
  Duration? _pausedWarmupRemaining;

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
  /// reps/weight in sync with what the Goal block ends up showing.
  bool _prefillRefreshedFromHistory = false;

  /// Guards [_onFinish]/[_onLeave]/[_onDiscard] against re-entrancy — all are
  /// async and otherwise callable again (double-tap, or Finish racing the
  /// close button) before the first call's writes/pop land.
  bool _busy = false;

  /// The live rest-countdown value, read fresh every frame — frozen at
  /// [_pausedRestRemaining] while paused, otherwise the wall-clock gap to
  /// [_restEndsAt] (never negative). Null whenever no rest is running, which
  /// doubles as "are we in the resting phase" for [_phaseKey]/[_buildPhase].
  Duration? get _restRemaining {
    final paused = _pausedRestRemaining;
    if (paused != null) return paused;
    final endsAt = _restEndsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(widget.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// The live warm-up-countdown value — same shape as [_restRemaining], and
  /// doubles as "is the warm-up phase showing" for [_phaseKey]/[_buildPhase].
  Duration? get _warmupRemaining {
    final paused = _pausedWarmupRemaining;
    if (paused != null) return paused;
    final endsAt = _warmupEndsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(widget.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

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
    // Only a genuinely fresh start opens on the warm-up phase — a resumed
    // session (even one with nothing logged yet) or one that already has a
    // done set skips straight to running, since re-showing it wouldn't mean
    // "before your first set" any more.
    if (widget.resume == null && _session.completedSetCount == 0 && !_session.isComplete) {
      _startWarmup();
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
      _resyncRestOnResume();
      _resyncWarmupOnResume();
      _tickElapsed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTicker?.dispose();
    _warmupTicker?.dispose();
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
  /// shows what was actually typed, not a reset. A never-touched set seeds
  /// from the computed [ProgressionGoal] — the plan's own prescription when
  /// there's no history for this exact set, or the double-progression
  /// suggestion once there is. "AMRAP" (to-failure, no history) has no
  /// number to seed, so reps is left blank for the user.
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

  /// Index-aligned against [history]'s *working* sets only.
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

  // ---- Transitions -----------------------------------------------------------

  void _onSetDone() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    HapticFeedback.lightImpact();
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
      _restTicker?.dispose();
      _restTicker = null;
      _restTotalSeconds = null;
      _restEndsAt = null;
      _elapsedTimer?.cancel();
      setState(() {});
      return;
    }
    // Rest is the plan's own value (Edit Workout's per-exercise rest, or its
    // "Default rest" bulk value) — the session counts down what Ziad
    // actually set, not a computed guess. `smartRestSeconds` stays as the
    // *seed* default a freshly-added exercise starts at (see the add sheet),
    // it just no longer overrides the plan at session time.
    _startRest(exercise.restSeconds);
  }

  void _startRest(int seconds) {
    _restTicker?.dispose();
    _restTicker = null;
    if (seconds <= 0) {
      setState(() {
        _restTotalSeconds = null;
        _restEndsAt = null;
      });
      return;
    }
    _restTotalSeconds = seconds;
    _restEndsAt = widget.now().add(Duration(seconds: seconds));
    setState(() {});
    _restTicker = createTicker(_onRestTick)..start();
  }

  /// The [_restTicker]'s per-frame callback — fires every rendered frame
  /// (~60fps) while resting, driving the premium sub-second countdown. Just
  /// a rebuild trigger; [_restRemaining] is what's actually displayed, and
  /// it's always recomputed fresh from [_restEndsAt] against [widget.now],
  /// so this can't drift or accumulate error the way summing per-tick deltas
  /// would.
  void _onRestTick(Duration elapsed) {
    if (!mounted) return;
    final remaining = _restRemaining;
    if (remaining == null) return;
    if (remaining <= Duration.zero) {
      HapticFeedback.heavyImpact();
      _endRest();
      return;
    }
    setState(() {});
  }

  /// Resyncs the rest countdown on app resume — the OS suspends `Ticker`
  /// callbacks while backgrounded, so without this a rest that actually
  /// finished while away would sit frozen instead of advancing to the next
  /// set. A no-op while paused (`_restEndsAt` is null then, frozen into
  /// [_pausedRestRemaining] instead) or when there's no rest running.
  void _resyncRestOnResume() {
    final remaining = _restRemaining;
    if (_restEndsAt != null && remaining != null && remaining <= Duration.zero) {
      _endRest();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _endRest() {
    _restTicker?.dispose();
    _restTicker = null;
    _restTotalSeconds = null;
    _restEndsAt = null;
    if (mounted) setState(() {});
  }

  /// Opens the one-shot pre-workout warm-up phase — same wall-clock-endsAt
  /// approach as [_startRest], just fixed at [_warmupSeconds] rather than a
  /// per-exercise rest window.
  void _startWarmup() {
    _warmupTicker?.dispose();
    _warmupTotalSeconds = _warmupSeconds;
    _warmupEndsAt = widget.now().add(const Duration(seconds: _warmupSeconds));
    _warmupTicker = createTicker(_onWarmupTick)..start();
  }

  /// The [_warmupTicker]'s per-frame callback — the [_onRestTick] analog.
  void _onWarmupTick(Duration elapsed) {
    if (!mounted) return;
    final remaining = _warmupRemaining;
    if (remaining == null) return;
    if (remaining <= Duration.zero) {
      HapticFeedback.heavyImpact();
      _endWarmup();
      return;
    }
    setState(() {});
  }

  /// The [_resyncRestOnResume] analog for the warm-up phase.
  void _resyncWarmupOnResume() {
    final remaining = _warmupRemaining;
    if (_warmupEndsAt != null && remaining != null && remaining <= Duration.zero) {
      _endWarmup();
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Ends the warm-up phase — reached both by the countdown hitting zero and
  /// by "Skip warm-up".
  void _endWarmup() {
    _warmupTicker?.dispose();
    _warmupTicker = null;
    _warmupTotalSeconds = null;
    _warmupEndsAt = null;
    if (mounted) setState(() {});
  }

  /// The [_adjustRest] analog for the warm-up phase.
  void _adjustWarmup(int delta) {
    final endsAt = _warmupEndsAt;
    if (endsAt == null) return;
    HapticFeedback.selectionClick();
    final nextEndsAt = endsAt.add(Duration(seconds: delta));
    if (!nextEndsAt.isAfter(widget.now())) {
      _endWarmup();
      return;
    }
    final remaining = nextEndsAt.difference(widget.now());
    _warmupEndsAt = nextEndsAt;
    final remainingCeilSeconds = _ceilSeconds(remaining);
    if (_warmupTotalSeconds != null && remainingCeilSeconds > _warmupTotalSeconds!) {
      _warmupTotalSeconds = remainingCeilSeconds;
    }
    setState(() {});
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
    HapticFeedback.selectionClick();
    final nextEndsAt = endsAt.add(Duration(seconds: delta));
    if (!nextEndsAt.isAfter(widget.now())) {
      _endRest();
      return;
    }
    final remaining = nextEndsAt.difference(widget.now());
    _restEndsAt = nextEndsAt;
    // Keep the ring sensible: grow the total if the adjustment pushed the
    // remaining time past what it was counting down from.
    final remainingCeilSeconds = _ceilSeconds(remaining);
    if (_restTotalSeconds != null && remainingCeilSeconds > _restTotalSeconds!) {
      _restTotalSeconds = remainingCeilSeconds;
    }
    setState(() {});
  }

  /// Pauses the workout: stops the elapsed clock, and — if a rest was
  /// actively counting down — freezes its remaining time rather than losing
  /// it. Model state ([LiveSession.pause]), so it's saved and survives
  /// leave/resume.
  void _onPause() {
    final now = widget.now();
    final endsAt = _restEndsAt;
    if (endsAt != null) {
      final remaining = endsAt.difference(now);
      _pausedRestRemaining = remaining.isNegative ? Duration.zero : remaining;
      _restTicker?.dispose();
      _restTicker = null;
      _restEndsAt = null;
    }
    final warmupEndsAt = _warmupEndsAt;
    if (warmupEndsAt != null) {
      final remaining = warmupEndsAt.difference(now);
      _pausedWarmupRemaining = remaining.isNegative ? Duration.zero : remaining;
      _warmupTicker?.dispose();
      _warmupTicker = null;
      _warmupEndsAt = null;
    }
    setState(() {
      _session = _session.pause(now: now);
    });
    _elapsedTimer?.cancel();
    unawaited(_sessionsRepo.saveSession(_session));
  }

  /// Resumes from [_onPause]: restarts the elapsed clock, and — if a rest
  /// was frozen — restores it from exactly where it left off.
  void _onResume() {
    final now = widget.now();
    final pausedRemaining = _pausedRestRemaining;
    if (pausedRemaining != null) {
      _pausedRestRemaining = null;
      _restEndsAt = now.add(pausedRemaining);
      _restTicker?.dispose();
      _restTicker = createTicker(_onRestTick)..start();
    }
    final pausedWarmupRemaining = _pausedWarmupRemaining;
    if (pausedWarmupRemaining != null) {
      _pausedWarmupRemaining = null;
      _warmupEndsAt = now.add(pausedWarmupRemaining);
      _warmupTicker?.dispose();
      _warmupTicker = createTicker(_onWarmupTick)..start();
    }
    setState(() {
      _session = _session.resume(now: now);
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
    _restTicker?.dispose();
    _restTicker = null;
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
    _restTicker?.dispose();
    _restTicker = null;
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
              _FrostedTopBar(
                child: CaptureTopBar(
                  title: _dayTitle(widget.day),
                  onClose: _onLeave,
                  titleColor: AppColors.ink2,
                  iconColor: AppColors.ink2,
                  chipColor: AppColors.surfaceRaised,
                  trailing: CaptureIconButton(
                    icon: Icons.delete_outline_rounded,
                    onTap: _onDiscard,
                    semanticLabel: 'Discard workout',
                    iconColor: AppColors.flare,
                    chipColor: AppColors.surfaceRaised,
                  ),
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
                      transitionBuilder: (child, animation) => reducedMotion(context)
                          ? FadeTransition(opacity: animation, child: child)
                          : FadeTransition(
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
    if (_warmupRemaining != null) return 'warmup';
    if (_restRemaining != null) return 'resting';
    return 'running:${_session.currentSet?.id}';
  }

  Widget _buildPhase() {
    if (_session.isComplete) return _buildCompleted();
    if (_warmupRemaining != null) return _buildWarmup();
    if (_restRemaining != null) return _buildResting();
    return _buildRunning();
  }

  Widget _buildRunning() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) {
      return const Center(child: Text('Nothing to do.'));
    }

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
    final comparison = compareToLastTime(
      previous: previousSet,
      actualReps: int.tryParse(_reps.text.trim()),
      actualWeightKg: double.tryParse(_weight.text.trim().replaceAll(',', '.')),
    );
    // Working-only position — warm-up ramp steps (if any) sit before this
    // in `exercise.sets` but aren't part of the numbered working sequence.
    final workingSetCount = exercise.sets.where((s) => s.type == SetType.working).length;
    final workingIndex = workingSetIndexOf(exercise, set);

    return _runningScaffold(
      content: [
        // Exercise header — consolidated: the name is the hero title, the
        // muscle group a quiet pill beside it. No standalone "Target: X"
        // line (that's now context inside the Goal card) and no separate
        // "SET N OF M" eyebrow (the chip row below is the one set-position
        // indicator).
        StaggeredReveal(index: 0, child: _exerciseHeader(exercise)),
        const SizedBox(height: AppSpacing.l),
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
          child: _GoalBlock(
            lastTimeLabel: lastTimeLabel,
            goal: goal,
            targetText: targetText,
            comparison: comparison,
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 3,
          child: Row(
            children: [
              _StepperField(
                label: 'Reps',
                controller: _reps,
                step: 1,
                onChanged: _onActualChanged,
              ),
              const SizedBox(width: AppSpacing.m),
              _StepperField(
                label: 'Weight (kg)',
                controller: _weight,
                step: 2.5,
                hint: '—',
                onChanged: _onActualChanged,
              ),
            ],
          ),
        ),
      ],
      done: StaggeredReveal(
        index: 4,
        child: PillButton(
          label: 'Done',
          icon: Icons.check_rounded,
          enabled: true,
          onTap: _onSetDone,
        ),
      ),
    );
  }

  /// Shared shell for the running/warm-up-running screens: [content] groups
  /// at the top with its own internal rhythm, [done] anchors to the bottom
  /// via a flexible gap rather than sitting wherever the content happens to
  /// end — no more dead void beneath it on tall screens. Still scrolls
  /// gracefully (the flexible gap just collapses to 0) when content plus the
  /// keyboard overflow a short screen.
  Widget _runningScaffold({required List<Widget> content, required Widget done}) {
    return LayoutBuilder(
      key: const ValueKey('running-list'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.m,
            AppSpacing.l,
            AppSpacing.l,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.m - AppSpacing.l),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...content, const Spacer(), done],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _exerciseHeader(SessionExercise exercise) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        exercise.name,
        style: AppText.cardTitle.copyWith(fontSize: 30, color: AppColors.ink),
      ),
      if (exercise.muscleGroup != null) ...[
        const SizedBox(height: AppSpacing.s),
        _MuscleGroupPill(label: exercise.muscleGroup!),
      ],
    ],
  );

  /// The pre-workout warm-up phase — shown once, before the first set of a
  /// genuinely fresh session (see [initState]). Deliberately reuses
  /// [_RestRing]/[_RestAdjustButton] wholesale rather than a parallel
  /// implementation: same fixed-size, sub-second, wall-clock countdown,
  /// distinct only in its eyebrow/copy/duration and the color it hangs off
  /// (Ember — this app's warm-up hue — instead of Rest's neutral ink3). This
  /// is the app's one warm-up (owner decision) — the old per-exercise ramp
  /// warm-up SETS have been retired.
  Widget _buildWarmup() {
    return Padding(
      key: const ValueKey('warmup'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(child: _Eyebrow('Pre-workout', color: AppColors.ember)),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Loosen up before your first set',
              style: AppText.meta.copyWith(color: AppColors.ink3),
            ),
          ),
          const Spacer(),
          Center(
            child: _RestRing(
              remaining: _warmupRemaining ?? Duration.zero,
              total: _warmupTotalSeconds ?? 1,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _RestAdjustButton(label: '-15s', onTap: () => _adjustWarmup(-15))),
              const SizedBox(width: 12),
              Expanded(child: _RestAdjustButton(label: '+15s', onTap: () => _adjustWarmup(15))),
            ],
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Skip warm-up',
            icon: Icons.skip_next_rounded,
            color: AppColors.ember,
            enabled: true,
            onTap: _endWarmup,
          ),
        ],
      ),
    );
  }

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
          // The ring is the centerpiece — split the space between the
          // eyebrow and the bottom controls evenly around it, rather than
          // letting it float high with all the slack dumped below "Next:".
          const Spacer(),
          Center(
            child: _RestRing(
              remaining: _restRemaining ?? Duration.zero,
              total: _restTotalSeconds ?? 1,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Next: $nextLabel',
              style: AppText.rowTitle.copyWith(color: AppColors.ink2),
            ),
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
            color: AppColors.pulse,
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
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Center(child: _Eyebrow('Workout complete', color: AppColors.pulse)),
        const SizedBox(height: 14),
        Center(
          child: _PopIn(
            child: Icon(Icons.check_circle_rounded, size: 56, color: AppColors.pulse),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.day.label,
          style: AppText.cardTitle.copyWith(fontSize: 24, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          '${_session.completedSetCount} of ${_session.totalSets} sets · ${elapsed.inMinutes} min',
          style: AppText.meta.copyWith(color: AppColors.pulse),
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
            color: AppColors.pulse,
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

/// The pre-workout warm-up phase's fixed default length — 5:00, chosen as a
/// reasonable one-size loosen-up window; configurable later, not now.
const int _warmupSeconds = 300;

/// A restrained, low-opacity lift for the Goal/Warm-up cards on dark — the
/// shared [AppShadows.pulse]/[AppShadows.ember] (tuned for light-mode pill
/// buttons) read as a bright neon halo against near-black, which isn't the
/// premium feel this screen wants. This is a much softer glow paired with a
/// plain neutral hairline border, so the color reads as a subtle accent
/// rather than the card's whole edge.
List<BoxShadow> _cardGlow(Color color) => [
  BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 8)),
];

// ---- Small building blocks ----------------------------------------------

/// The in-session top bar as a translucent, blurred material rather than a
/// flat opaque strip — chrome that reads as a physical layer over the
/// session, matching the ground beneath it in hue so it darkens rather than
/// washes out. `prefers-reduced-transparency`-style: falls back to a solid
/// (unblurred) surface when reduced motion is on, since blur is itself a
/// subtle, continuous visual effect best paired with the rest of the
/// session's motion.
class _FrostedTopBar extends StatelessWidget {
  const _FrostedTopBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) {
      return ColoredBox(color: AppColors.ground, child: child);
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: AppColors.ground.withValues(alpha: 0.72),
          child: child,
        ),
      ),
    );
  }
}

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

/// The session's overall progress — springs to [value] from wherever it
/// currently sits (rather than a fixed-duration tween restarting from 0 each
/// time), so a set completing right after a previous spring settled doesn't
/// visibly reset before re-animating.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, value: widget.value);

  @override
  void didUpdateWidget(covariant _ProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (reducedMotion(context)) {
      _controller.value = widget.value;
    } else {
      _controller.springTo(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LinearProgressIndicator(
            value: _controller.value,
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
            PressableScale(
              child: InkWell(
                key: const Key('pause-toggle'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTogglePause!();
                },
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 16,
                        color: isPaused ? AppColors.pulse : AppColors.ink3,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPaused ? 'Resume' : 'Pause',
                        style: AppText.meta.copyWith(
                          color: isPaused ? AppColors.pulse : AppColors.ink3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Last-time + Goal card — the point of the running phase per the
/// "genuinely smarter" pass: an elevated dark card (a plain hairline border
/// plus [_cardGlow]'s restrained pulse-tinted lift, not a bright halo) so
/// Goal reads as the dominant, hero element through hierarchy — biggest,
/// boldest, on its own surface — not through any new motion. "Last time" is
/// a quiet supporting line, and the plan's own rep target sits underneath as
/// quieter context still. No animation beyond the shared entrance stagger.
class _GoalBlock extends StatelessWidget {
  const _GoalBlock({
    required this.lastTimeLabel,
    required this.goal,
    this.targetText,
    this.comparison,
  });

  final String lastTimeLabel;
  final ProgressionGoal goal;
  final String? targetText;

  /// Today's in-progress verdict against [lastTimeLabel] (see
  /// [compareToLastTime]) — null whenever there's nothing real to compare
  /// yet (first time ever, or no rep count typed in), in which case no
  /// badge shows at all.
  final SetProgressComparison? comparison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: _cardGlow(AppColors.pulse),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 14, color: AppColors.pulse),
              const SizedBox(width: 6),
              Text(
                'GOAL',
                style: AppText.meta.copyWith(
                  color: AppColors.pulse,
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
            style: AppText.heroNumber.copyWith(
              fontSize: 40,
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            'Last time: $lastTimeLabel',
            key: const Key('last-time-label'),
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          if (comparison != null) _ProgressVerdictBadge(comparison: comparison!),
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
        color: AppColors.surfaceRaised,
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
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2, width: 1.4),
          ),
          child: Text(
            label,
            style: AppText.button.copyWith(fontSize: 15, color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

/// A premium tap-to-step reps/weight input (Feature C) — the same
/// [TextField] the plain field always used (typing directly into it, the
/// fallback, still works exactly as before — nothing about that path
/// changed), now flanked by ± stepper buttons that nudge the value by
/// [step] with a selection-click haptic and a small spring "punch" on the
/// field itself, the "alive" feedback the plain field never had.
class _StepperField extends StatefulWidget {
  const _StepperField({
    required this.label,
    required this.controller,
    required this.step,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final TextEditingController controller;

  /// How much each ± tap moves the value — whole reps (1) or a plate-sized
  /// weight jump (2.5kg), passed in per call site.
  final double step;
  final VoidCallback onChanged;
  final String? hint;

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> with SingleTickerProviderStateMixin {
  late final AnimationController _punch = AnimationController(vsync: this, value: 1);

  double? get _value {
    final raw = widget.controller.text.trim().replaceAll(',', '.');
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  /// Nudges the value by [delta] and writes it straight back into
  /// [widget.controller] — the same controller the typed fallback edits, so
  /// both paths always agree on what's actually entered.
  void _step(double delta) {
    HapticFeedback.selectionClick();
    final raw = (_value ?? 0) + delta;
    final next = raw < 0 ? 0.0 : raw;
    widget.controller.text = _trimWeight(next);
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    if (reducedMotion(context)) {
      _punch.value = 1;
    } else {
      _punch.value = 0.88;
      _punch.springTo(1, spring: AppSprings.bounce);
    }
    widget.onChanged();
  }

  @override
  void dispose() {
    _punch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.6),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              _StepButton(icon: Icons.remove_rounded, onTap: () => _step(-widget.step)),
              const SizedBox(width: 6),
              Expanded(
                child: AnimatedBuilder(
                  animation: _punch,
                  builder: (context, child) => Transform.scale(scale: _punch.value, child: child),
                  child: TextField(
                    controller: widget.controller,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    cursorColor: AppColors.ember,
                    style: AppText.rowTitle.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    onChanged: (_) => widget.onChanged(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.hint,
                      hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                      filled: true,
                      fillColor: AppColors.surfaceRaised,
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
                ),
              ),
              const SizedBox(width: 6),
              _StepButton(icon: Icons.add_rounded, onTap: () => _step(widget.step)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single ± tap target for [_StepperField] — a quiet outlined square
/// beside the field, pressed feedback via the shared [PressableScale].
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip + 4),
        child: Container(
          width: 40,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.chip + 4),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Icon(icon, size: 18, color: AppColors.ink2),
        ),
      ),
    );
  }
}

/// The Progress verdict callout (Feature B) — how today's in-progress set
/// stacks up against the same set from last time (see [compareToLastTime]):
/// reps %, weight delta, and volume % rolled into one verdict. Lives right
/// under "Last time" in the Goal card, since that's the number it's judged
/// against, and updates live on every keystroke/step. Punches (a small
/// spring scale) only when the verdict/label actually changes — the same
/// settle-in idiom as the numbered set chips — so it doesn't just flicker
/// on every unrelated rebuild.
class _ProgressVerdictBadge extends StatefulWidget {
  const _ProgressVerdictBadge({required this.comparison});

  final SetProgressComparison comparison;

  @override
  State<_ProgressVerdictBadge> createState() => _ProgressVerdictBadgeState();
}

class _ProgressVerdictBadgeState extends State<_ProgressVerdictBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(covariant _ProgressVerdictBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final same =
        oldWidget.comparison.verdict == widget.comparison.verdict &&
        oldWidget.comparison.overallChangePercent.round() ==
            widget.comparison.overallChangePercent.round();
    if (same) return;
    if (reducedMotion(context)) {
      _scale.value = 1;
    } else {
      _scale.value = 0.9;
      _scale.springTo(1, spring: AppSprings.bounce);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparison = widget.comparison;
    final (icon, color, word) = verdictStyle(comparison.verdict);
    final pct = comparison.overallChangePercent.round();
    final label = comparison.verdict == ProgressVerdict.matched
        ? word
        : '$word ${pct > 0 ? '+' : ''}$pct%';

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: Container(
        key: const Key('progress-verdict'),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
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

class _SetChip extends StatefulWidget {
  const _SetChip({required this.number, required this.state});

  final int number;
  final _ChipState state;

  @override
  State<_SetChip> createState() => _SetChipState();
}

class _SetChipState extends State<_SetChip> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(vsync: this, value: _targetScale(widget.state));

  double _targetScale(_ChipState state) => state == _ChipState.current ? 1.1 : 1.0;

  @override
  void didUpdateWidget(covariant _SetChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    final target = _targetScale(widget.state);
    if (reducedMotion(context)) {
      _scale.value = target;
      return;
    }
    // A set completing is the one momentum moment here — a set going
    // current/upcoming just settles, no overshoot earned.
    final spring = widget.state == _ChipState.done ? AppSprings.bounce : AppSprings.standard;
    _scale.springTo(target, spring: spring);
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
              '${widget.number}',
              style: AppText.meta.copyWith(
                color: state == _ChipState.current ? Colors.white : AppColors.ink3,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final popped = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
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

/// The premium rest countdown — a ring sweeping down continuously (not
/// stepped) over the rest window, with the remaining time centered inside
/// at sub-second precision. Warm gray/ink, per the approved "rest" identity
/// (Ember stays reserved for the current set, Pulse for done) — a vivid hue
/// here would compete with that meaning.
///
/// The ring and the digits stay a fixed size at all times — the "alive"
/// feel comes from a slow stroke color/width ease on the sweep itself
/// ([_glow]), never from scaling the whole thing (see M2: constant-size
/// timer).
class _RestRing extends StatefulWidget {
  const _RestRing({required this.remaining, required this.total});

  final Duration remaining;
  final int total;

  @override
  State<_RestRing> createState() => _RestRingState();
}

class _RestRingState extends State<_RestRing> with TickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// Absorbs a discontinuous jump in [_trueProgress] (a ±15s adjustment) as a
  /// correction that starts at the jump's size and springs back to zero —
  /// the ring keeps tracking wall-clock time exactly every frame, but a
  /// sudden retarget visibly *springs* to the new fraction instead of
  /// snapping. The normal continuous per-frame decay between adjustments
  /// never touches this (it's already smooth by construction).
  late final AnimationController _correction = AnimationController.unbounded(vsync: this)..value = 0;

  double? _lastProgress;

  double get _trueProgress {
    final totalMs = widget.total * 1000;
    return totalMs <= 0 ? 0.0 : (widget.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _RestRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = _lastProgress;
    final next = _trueProgress;
    // A normal tick decays by a fraction of a percent; only a ±15s jump
    // moves it enough to cross this threshold, so this reliably tells the
    // two apart regardless of exact rebuild cadence.
    if (last != null && (next - last).abs() > 0.01 && !reducedMotion(context)) {
      final jump = last - next;
      _correction.value = _correction.value + jump;
      _correction.springTo(0, spring: AppSprings.standard);
    }
    _lastProgress = next;
  }

  @override
  void dispose() {
    _glow.dispose();
    _correction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _lastProgress ??= _trueProgress;
    final time = _restTimeParts(widget.remaining);
    // The outer box is wider than the drawn ring (still 240x240, unchanged)
    // to give the fixed-width label ([_RestTimeLabel]) headroom for its
    // widest case ("M:SS.CC") without ever needing to reflow or clip.
    return SizedBox(
      width: 300,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_glow, _correction]),
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_glow.value);
              final progress = (_trueProgress + _correction.value).clamp(0.0, 1.0);
              return CustomPaint(
                size: const Size(240, 240),
                painter: _RestRingPainter(progress: progress, glow: t),
              );
            },
          ),
          _RestTimeLabel(time: time),
        ],
      ),
    );
  }
}

/// The rest ring's sub-second readout: a bold whole-second part ("1:54" at/
/// above a minute, "45" under it) plus a quieter ".CC" hundredths suffix.
/// Each part lives in a [_FixedSlot] sized for its widest possible content,
/// so neither the digits nor the ring around them resize or shift as the
/// digit count changes crossing a minute boundary or ticking down — only
/// the glyphs inside each slot update.
class _RestTimeLabel extends StatelessWidget {
  const _RestTimeLabel({required this.time});

  final ({String whole, String centis}) time;

  static final _wholeStyle = AppText.heroNumber.copyWith(fontSize: 50, color: AppColors.ink);
  static final _centisStyle = AppText.heroNumber.copyWith(fontSize: 26, color: AppColors.ink2);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${time.whole}${time.centis}',
      excludeSemantics: true,
      child: Row(
        key: const Key('rest-time-label'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _FixedSlot(
            // Widest realistic rest window: single-digit minutes, "M:SS".
            reference: '9:59',
            alignment: Alignment.centerRight,
            style: _wholeStyle,
            child: Text(time.whole, key: const Key('rest-time-whole'), style: _wholeStyle),
          ),
          _FixedSlot(
            reference: '.99',
            alignment: Alignment.centerLeft,
            style: _centisStyle,
            child: Text(time.centis, key: const Key('rest-time-centis'), style: _centisStyle),
          ),
        ],
      ),
    );
  }
}

/// Reserves layout width for [reference] (the slot's widest possible
/// content) and aligns [child] within it per [alignment] — so [child] can
/// grow/shrink its own character count without the slot itself, or anything
/// laid out around it, reflowing.
class _FixedSlot extends StatelessWidget {
  const _FixedSlot({
    required this.reference,
    required this.child,
    required this.style,
    required this.alignment,
  });

  final String reference;
  final Widget child;
  final TextStyle style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: alignment,
      children: [
        Opacity(opacity: 0, child: Text(reference, style: style)),
        child,
      ],
    );
  }
}

/// Splits [remaining] into the premium countdown's two-tier display: the
/// bold whole-second part ("1:54" at/above a minute, "45" under it) and a
/// quieter ".CC" hundredths suffix — a common stopwatch convention that
/// reads as precise without the decimals overwhelming the big numeral.
({String whole, String centis}) _restTimeParts(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final totalCentis = clamped.inMilliseconds ~/ 10;
  final minutes = totalCentis ~/ 6000;
  final seconds = (totalCentis % 6000) ~/ 100;
  final centis = totalCentis % 100;
  final whole = minutes > 0
      ? '$minutes:${seconds.toString().padLeft(2, '0')}'
      : seconds.toString().padLeft(2, '0');
  return (whole: whole, centis: '.${centis.toString().padLeft(2, '0')}');
}

class _RestRingPainter extends CustomPainter {
  const _RestRingPainter({required this.progress, required this.glow});

  /// 1.0 = the full rest window remains, 0.0 = rest is over.
  final double progress;

  /// 0..1 easing value driving the sweep's stroke width/opacity — the
  /// timer's "alive" pulse. Never affects layout size, only paint.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final track = Paint()
      ..color = AppColors.hairline2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final sweep = Paint()
      ..color = AppColors.ink2.withValues(alpha: 0.82 + 0.18 * glow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 + 1.5 * glow
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
  bool shouldRepaint(covariant _RestRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.glow != glow;
}

/// A one-shot scale-in — used for the completion checkmark.
/// The completion checkmark's one-shot arrival — the one other genuinely
/// earned momentum moment (alongside a set chip completing), so it springs
/// in with the same slight, controlled overshoot rather than a scripted
/// multi-wiggle elastic curve.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, value: 0);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery isn't available yet in initState — this is the earliest
    // safe place to read it, and it only needs to run once, on arrival.
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.springTo(1, spring: AppSprings.bounce);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
      child: widget.child,
    );
  }
}
