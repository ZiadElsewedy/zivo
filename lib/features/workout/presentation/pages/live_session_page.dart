import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
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
import '../../domain/set_outcome.dart';
import '../../domain/set_type.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_plan_repository.dart';
import '../../domain/workout_session_repository.dart';
import '../../../music/domain/music_connection.dart';
import '../../../music/domain/music_controller.dart';
import '../../../music/domain/now_playing.dart';
import '../../../music/music_config.dart';
import '../../../music/presentation/music_artwork.dart';
import '../../../music/presentation/music_player_page.dart';
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

  /// True for the brief "completion beat" hold in [_afterResolvingCurrentSet]
  /// — long enough for the just-resolved set's chip to visibly spring into
  /// its done/checkmark state before the screen advances to rest/the next
  /// phase (see that method's doc comment). The Done/Skip/Back controls stay
  /// on-screen through the hold (nothing else to show yet), so this guards
  /// them against a tap landing in that window and resolving a set that's
  /// already mid-resolution.
  bool _resolvingSet = false;

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
      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickElapsed(),
      );
    }
    // Only a genuinely fresh start opens on the warm-up phase — a resumed
    // session (even one with nothing logged yet) or one that already has a
    // done set skips straight to running, since re-showing it wouldn't mean
    // "before your first set" any more.
    if (widget.resume == null &&
        _session.completedSetCount == 0 &&
        !_session.isComplete) {
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
        // §3.2 invariant 4: a split's history is its own — scoped to THIS
        // session's split (splitId == planId), never another split's, even
        // when they happen to share an exerciseId (e.g. one is a duplicate
        // of the other). Without the planId filter, "previous performance"
        // could silently show a different split's numbers.
        _pastSessions = sessions
            .where((s) => s.id != _session.id && s.planId == _session.planId)
            .toList(growable: false);
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
      _weight.text = set.actualWeightKg != null
          ? _trimWeight(set.actualWeightKg!)
          : '';
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
      _session = _session.updateSet(
        exercise.id,
        set.id,
        actualReps: reps,
        actualWeightKg: weight,
      );
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
    final workingHistory = history.sets
        .where((s) => s.type == SetType.working)
        .toList(growable: false);
    final index = workingSetIndexOf(exercise, set);
    if (index < 0 || index >= workingHistory.length) return null;
    return workingHistory[index];
  }

  /// The most recently COMPLETED set before [set] within [exercise], THIS
  /// session — distinct from [_previousSetFor], which reaches back to a
  /// past session. Null for the exercise's first set, or when nothing
  /// before it has been completed yet (a skip doesn't count: it carries no
  /// actuals to compare against).
  LoggedSet? _previousSetInSession(SessionExercise exercise, LoggedSet set) {
    LoggedSet? prev;
    for (final s in exercise.sets) {
      if (s.id == set.id) break;
      if (s.done) prev = s;
    }
    return prev;
  }

  // ---- Transitions -----------------------------------------------------------

  void _onSetDone() {
    if (_resolvingSet) return;
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
    });
    // What actually got logged, not a generic "Set done" — the same
    // formatting the end-of-workout review uses, so the confirmation and
    // the review agree on exactly what was recorded.
    final resolved = _setById(exercise.id, set.id);
    final undoMessage = resolved == null
        ? 'Set logged'
        : _doneSnackbarSummary(resolved);
    _afterResolvingCurrentSet(
      exercise.id,
      set.id,
      exercise.restSeconds,
      undoMessage: undoMessage,
      undoIcon: Icons.check_circle_rounded,
      undoIconColor: AppColors.pulse,
    );
  }

  /// Looks up a set's current (post-resolution) state by id — used right
  /// after [LiveSession.markSetDone] to read back the actuals it settled on
  /// (typed value, or the fixed-target fallback) for the Undo snackbar.
  LoggedSet? _setById(String exerciseId, String setId) {
    for (final e in _session.exercises) {
      if (e.id != exerciseId) continue;
      for (final s in e.sets) {
        if (s.id == setId) return s;
      }
    }
    return null;
  }

  /// The Skip affordance — advances past the current set exactly like Done,
  /// but logs no volume (see [LiveSession.markSetSkipped]). Deliberately
  /// preserves whatever's typed in the reps/weight fields on the set itself
  /// (an abandoned draft the end-of-workout review can still surface) rather
  /// than reading/clearing them the way Done does.
  void _onSetSkip() {
    if (_resolvingSet) return;
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _session = _session.markSetSkipped(exercise.id, set.id);
    });
    _afterResolvingCurrentSet(
      exercise.id,
      set.id,
      exercise.restSeconds,
      undoMessage: 'Set skipped',
      undoIcon: Icons.remove_circle_outline_rounded,
      undoIconColor: AppColors.ink3,
    );
  }

  /// Shared tail for [_onSetDone]/[_onSetSkip]: completes the session if
  /// that was the last pending set (else starts rest), autosaves, refreshes
  /// the input prefill for whatever's now current, and offers an Undo
  /// snackbar targeting exactly the (exerciseId, setId) just resolved — not
  /// "whatever's current now", since current has already moved on by the
  /// time this shows.
  ///
  /// The actual advance is held behind a brief beat (see [_resolvingSet]):
  /// [_session] has already updated by the time this runs (the caller's own
  /// `setState` in [_onSetDone]/[_onSetSkip] already committed it), so
  /// `_SetChipRow` is already re-rendering the just-resolved chip in its
  /// done/checkmark state on this very frame — but without a hold, the phase
  /// advance below (`_startRest`/`complete`, which flips [_phaseKey]) would
  /// fire in that SAME frame too, and the whole running screen — chip
  /// included — would already be cross-fading away before the chip's own
  /// [AppSprings.bounce] spring has had any time to actually register. This
  /// hold is what turns "instant swap" into "see it complete, then advance."
  /// Skipped under reduced motion, where there's no spring to wait for.
  void _afterResolvingCurrentSet(
    String exerciseId,
    String setId,
    int restSeconds, {
    required String undoMessage,
    required IconData undoIcon,
    required Color undoIconColor,
  }) {
    _resolvingSet = true;
    final hold = reducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    Future<void>.delayed(hold, () {
      _resolvingSet = false;
      if (!mounted) return;
      setState(() {
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
      } else {
        // Rest is the plan's own value (Edit Workout's per-exercise rest, or
        // its "Default rest" bulk value) — the session counts down what Ziad
        // actually set, not a computed guess. `smartRestSeconds` stays as the
        // *seed* default a freshly-added exercise starts at (see the add
        // sheet), it just no longer overrides the plan at session time.
        _startRest(restSeconds);
      }
      _showUndoSnackbar(
        undoMessage,
        exerciseId,
        setId,
        icon: undoIcon,
        iconColor: undoIconColor,
      );
    });
  }

  /// Offers a brief window to reverse the Done/Skip that was just tapped.
  /// Fires on BOTH outcomes, not just skip — an accidental advance can just
  /// as easily be a wrong Done (Ziad's actual incident) as a wrong Skip. The
  /// leading icon mirrors the same done/skipped language `_SetChip` and the
  /// end-of-workout review already use, so the confirmation reads as the
  /// same system rather than a generic system snackbar.
  void _showUndoSnackbar(
    String message,
    String exerciseId,
    String setId, {
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
          // Lifted clear of the bottom action zone (the phase's own primary
          // button) — the toast confirms an action, it must never cover the
          // next one.
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 92),
          content: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppText.button.copyWith(
                    color: AppColors.ink,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.pulse,
            onPressed: () => _undoOutcome(exerciseId, setId),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  /// The Back control — walks back exactly one set: whichever
  /// [LiveSession.previousResolvedSet] currently is. Tapping repeatedly
  /// walks back further, one set at a time; anything beyond that is the
  /// end-of-workout review's job, not this control's.
  void _onBack() {
    // Guards against racing the pending delayed callback in
    // `_afterResolvingCurrentSet` — see `_resolvingSet`.
    if (_resolvingSet) return;
    final prev = _session.previousResolvedSet;
    if (prev == null) return;
    _undoOutcome(prev.$1, prev.$2.id);
  }

  /// The shared undo primitive behind both the Undo snackbar and the Back
  /// control: clears [setId]'s outcome back to pending. If resolving that
  /// set was what completed the session, un-completes it too (status back
  /// to active, elapsed timer restarted) — an Undo/Back must be able to
  /// reverse the very last set of a workout, not just ones mid-flow.
  void _undoOutcome(String exerciseId, String setId) {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    final wasComplete = _session.isComplete;
    setState(() {
      _session = _session.clearOutcome(exerciseId, setId);
      if (wasComplete) _session = _session.reopen();
    });
    unawaited(_sessionsRepo.saveSession(_session));
    // Whatever rest/warm-up phase the resolved action kicked off no longer
    // applies to a set that's pending again — drop it and land back on the
    // running screen for that set.
    _restTicker?.dispose();
    _restTicker = null;
    _restTotalSeconds = null;
    _restEndsAt = null;
    _pausedRestRemaining = null;
    if (wasComplete && !_session.isPaused) {
      _elapsedTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickElapsed(),
      );
    }
    _prefillInputs();
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
      // A short built-in platform chime — audible completion feedback for a
      // countdown the user may not be looking at, without pulling in an
      // audio-player dependency for one system sound.
      unawaited(SystemSound.play(SystemSoundType.alert));
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
    if (_restEndsAt != null &&
        remaining != null &&
        remaining <= Duration.zero) {
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
    if (_warmupEndsAt != null &&
        remaining != null &&
        remaining <= Duration.zero) {
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
    if (_warmupTotalSeconds != null &&
        remainingCeilSeconds > _warmupTotalSeconds!) {
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
    if (_restTotalSeconds != null &&
        remainingCeilSeconds > _restTotalSeconds!) {
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
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickElapsed(),
    );
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
    unawaited(plans.savePlan(_currentPlan(plans).advanceCursor()));
    unawaited(sessions.saveSession(_session));
    Navigator.of(context).pop();
  }

  /// The freshest known copy of [widget.plan], looked up by id from the
  /// repository's live split cache rather than trusting the snapshot
  /// captured when this page was pushed. That snapshot can go stale by the
  /// time a workout finishes — the plan may have been edited, reordered, or
  /// re-imported mid-session — and [WorkoutPlanRepository.savePlan] writes
  /// the WHOLE `days` array back, so advancing the cursor on a stale
  /// snapshot would silently revert any such concurrent edit and could
  /// desync the cursor from the plan's actual day order. Falls back to
  /// [widget.plan] itself if it's no longer among the saved splits (e.g.
  /// deleted mid-session).
  WorkoutPlan _currentPlan(WorkoutPlanRepository plans) {
    for (final split in plans.splits) {
      if (split.id == widget.plan.id) return split;
    }
    return widget.plan;
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
  ///
  /// `completedSetCount == 0` deliberately still reads as "empty" even when
  /// some sets were skipped: `completedSetCount` never counts a skip (see
  /// [LiveSession.completedSetCount]), so a session where the user skipped
  /// several sets and completed none — nothing actually performed, no logged
  /// volume — is genuinely empty by the same standard as one nothing was
  /// touched on at all. A skip that also left a draft still isn't "empty"
  /// either way, since [LiveSession.hasDraftActuals] already excludes
  /// skipped sets from counting as a draft.
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
            child: Text(
              'Keep going',
              style: AppText.button.copyWith(color: AppColors.ink3),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Discard',
              style: AppText.button.copyWith(color: AppColors.flareText),
            ),
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
                    // Neutral, same weight as Close — a destructive action
                    // still gated behind its own confirm dialog shouldn't
                    // also be the loudest, most eye-catching thing in the
                    // bar. Flare stays reserved for the confirm dialog's
                    // actual "Discard" button, where committing to it is
                    // the whole point.
                    iconColor: AppColors.ink3,
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
                      transitionBuilder: (child, animation) =>
                          reducedMotion(context)
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
                      child: KeyedSubtree(
                        key: ValueKey(_phaseKey),
                        child: _buildPhase(),
                      ),
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
    final intraSessionDelta = _intraSessionDeltaLabel(
      previous: _previousSetInSession(exercise, set),
      actualReps: int.tryParse(_reps.text.trim()),
      actualWeightKg: double.tryParse(_weight.text.trim().replaceAll(',', '.')),
    );
    // Working-only position — warm-up ramp steps (if any) sit before this
    // in `exercise.sets` but aren't part of the numbered working sequence.
    final workingSetCount = exercise.sets
        .where((s) => s.type == SetType.working)
        .length;
    final workingIndex = workingSetIndexOf(exercise, set);

    return _runningScaffold(
      top: [
        // The workout's now-playing companion. Index 0 is reserved for it
        // unconditionally (rather than only when it will actually render a
        // card) so the indices below never have to branch on
        // `kMusicEnabled` — an empty stagger slot is invisible. Unlike
        // `_RestPhase`'s graceful degrade to nothing, this slot renders on
        // every working set, so it always shows the card or a connect chip
        // — see `_SessionNowPlaying`.
        if (kMusicEnabled) ...[
          StaggeredReveal(
            index: 0,
            child: _SessionNowPlaying(
              controller: AppScope.of(context).requireMusic,
            ),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        // Exercise header — consolidated: the name is the hero title, the
        // muscle group a quiet pill beside it. No standalone "Target: X"
        // line (that's now context inside the Goal card) and no separate
        // "SET N OF M" eyebrow (the chip row below is the one set-position
        // indicator).
        StaggeredReveal(index: 1, child: _exerciseHeader(exercise)),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 2,
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
      ],
      hero: [
        // The hero: a lifted card carrying the computed goal, the point of
        // this whole screen — everything above just orients the user to it.
        StaggeredReveal(
          index: 3,
          child: _GoalBlock(
            lastTimeLabel: lastTimeLabel,
            goal: goal,
            targetText: targetText,
            comparison: comparison,
            intraSessionDeltaLabel: intraSessionDelta,
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        StaggeredReveal(
          index: 4,
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
        index: 5,
        child: _ActionCluster(
          onBack: _session.previousResolvedSet != null ? _onBack : null,
          onSkip: _onSetSkip,
          onDone: _onSetDone,
        ),
      ),
    );
  }

  /// Shared shell for the running/warm-up-running screens. [top] (the
  /// exercise header + set chips) and [done] (the action cluster) stay put;
  /// [hero] (the Goal card + steppers) sits between two flexible gaps rather
  /// than one dump zone below everything — on a tall screen that pulls the
  /// hero cluster toward the middle of the available space instead of
  /// leaving it stranded up top with a void beneath, while [done] keeps a
  /// bit of breathing room above it instead of sitting flush on the last
  /// gap. Both gaps collapse to 0 together when content plus the keyboard
  /// overflow a short screen — same graceful-degradation contract as before.
  Widget _runningScaffold({
    required List<Widget> top,
    required List<Widget> hero,
    required Widget done,
  }) {
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
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - AppSpacing.m - AppSpacing.l,
              ),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...top,
                  const Spacer(flex: 3),
                  ...hero,
                  const Spacer(flex: 2),
                  done,
                ],
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
    // Same scroll-safe shell `_runningScaffold` uses (LayoutBuilder +
    // SingleChildScrollView + IntrinsicHeight, `Spacer`s collapsing to 0
    // when content doesn't fit) — this phase has no text input so a
    // keyboard is never the trigger, but a very short device on its own
    // could otherwise overflow a bare `Spacer`-filled Column with no
    // fallback at all.
    return LayoutBuilder(
      key: const ValueKey('warmup'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 44),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: _Eyebrow(
                      'Pre-workout',
                      color: AppColors.ember,
                      icon: AppIcons.streak,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                      Expanded(
                        child: _RestAdjustButton(
                          label: '-15s',
                          icon: AppIcons.minus,
                          onTap: () => _adjustWarmup(-15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RestAdjustButton(
                          label: '+15s',
                          icon: AppIcons.add,
                          onTap: () => _adjustWarmup(15),
                        ),
                      ),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildResting() {
    final nextLabel = _nextUpLabel();
    // Same scroll-safe shell as `_buildWarmup`/`_runningScaffold` — see
    // `_buildWarmup`'s comment.
    return LayoutBuilder(
      key: const ValueKey('resting'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 44),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: _Eyebrow(
                      'Rest',
                      color: AppColors.ink2,
                      icon: AppIcons.pause,
                    ),
                  ),
                  // The ring is the centerpiece — split the space between the
                  // eyebrow and the bottom controls evenly around it, rather
                  // than letting it float high with all the slack dumped
                  // below "Next:".
                  const Spacer(),
                  // Song-on-top-of-ring when music is connected + playing —
                  // one cohesive unit, not two stacked cards (see
                  // `_RestPhase`'s doc comment). Byte-identical to the plain
                  // `Center(child: _RestRing(...))` this replaces whenever
                  // there's nothing to show above it — no music, no gap, no
                  // chip (unlike the logging slot, this screen is
                  // Spacer-balanced around the ring, and a chip would nag
                  // during rest).
                  _RestPhase(
                    ring: _RestRing(
                      remaining: _restRemaining ?? Duration.zero,
                      total: _restTotalSeconds ?? 1,
                    ),
                    controller: kMusicEnabled
                        ? AppScope.of(context).requireMusic
                        : null,
                  ),
                  const SizedBox(height: 18),
                  Column(
                    children: [
                      Text(
                        'UP NEXT',
                        style: AppText.meta.copyWith(
                          color: AppColors.ink3,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        nextLabel,
                        textAlign: TextAlign.center,
                        style: AppText.rowTitle.copyWith(
                          color: AppColors.ink2,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _RestAdjustButton(
                          label: '-15s',
                          icon: AppIcons.minus,
                          onTap: () => _adjustRest(-15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RestAdjustButton(
                          label: '+15s',
                          icon: AppIcons.add,
                          onTap: () => _adjustRest(15),
                        ),
                      ),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompleted() {
    final elapsed = _session.elapsed;
    // Every exercise with at least one resolved (done or skipped) set —
    // deliberately not `doneSetCount > 0` any more, since an exercise whose
    // only sets were skipped still needs to show up here to be reviewable.
    final reviewedExercises = _session.exercises
        .where((e) => e.sets.any((s) => !s.pending))
        .toList();
    return ListView(
      key: const ValueKey('completed-list'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Center(
          child: _Eyebrow(
            'Workout complete',
            color: AppColors.pulse,
            icon: AppIcons.check,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: _PopIn(
            child: Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: AppColors.pulse,
            ),
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
        // Review — every resolved set, flagging skips. Tap any row to fix
        // it before Finish commits: mark a skip actually-done with the real
        // reps/weight, or correct a logged actual. Nothing here is final
        // until Finish (§3.4 review-gate pattern, same idea as the AI
        // import's mandatory review step).
        for (final (i, exercise) in reviewedExercises.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StaggeredReveal(
              index: i,
              child: _ReviewExerciseGroup(
                exercise: exercise,
                onEditSet: (set, position) =>
                    _reviewSet(exercise, set, position),
              ),
            ),
          ),
        const SizedBox(height: 14),
        StaggeredReveal(
          index: reviewedExercises.length,
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

  /// Opens the review-edit sheet for one resolved set and applies the
  /// result: marks a skip actually-done (or just corrects a completed set's
  /// actuals) — either way the set's outcome ends up [SetOutcome.completed],
  /// since reviewing a set IS performing it. `null` (sheet dismissed without
  /// saving) leaves the set untouched.
  Future<void> _reviewSet(
    SessionExercise exercise,
    LoggedSet set,
    int position,
  ) async {
    final result = await showModalBottomSheet<(int?, double?)>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SetReviewSheet(
        title: '${exercise.name} · Set $position',
        wasSkipped: set.skipped,
        initialReps: set.actualReps,
        initialWeight: set.actualWeightKg,
      ),
    );
    if (result == null || !mounted) return;
    final (reps, weight) = result;
    setState(() {
      _session = _session.updateSet(
        exercise.id,
        set.id,
        actualReps: reps,
        actualWeightKg: weight,
        outcome: SetOutcome.completed,
      );
    });
    unawaited(_sessionsRepo.saveSession(_session));
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
String _trimWeight(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

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

/// "+2.5kg from your previous set" / "+2 reps from your previous set" — a
/// literal same-session delta against [previous] (the exercise's
/// immediately-preceding COMPLETED set this session), distinct from the
/// cross-session [SetProgressComparison] badge (which judges against last
/// week). Weight wins when both changed — the more meaningful signal on a
/// loaded exercise — reps only when weight didn't change or isn't tracked.
/// Null when there's no previous set yet, or nothing actually changed.
String? _intraSessionDeltaLabel({
  required LoggedSet? previous,
  required int? actualReps,
  required double? actualWeightKg,
}) {
  if (previous == null) return null;
  final prevWeight = previous.actualWeightKg;
  if (prevWeight != null &&
      actualWeightKg != null &&
      actualWeightKg != prevWeight) {
    final delta = actualWeightKg - prevWeight;
    return '${delta > 0 ? '+' : ''}${_trimWeight(delta)}kg from your previous set';
  }
  final prevReps = previous.actualReps;
  if (prevReps != null && actualReps != null && actualReps != prevReps) {
    final delta = actualReps - prevReps;
    return '${delta > 0 ? '+' : ''}$delta rep${delta.abs() == 1 ? '' : 's'} from your previous set';
  }
  return null;
}

/// "60kg × 8" — omits either half when unset; "First time" when there's no
/// previous performance to show at all (never trained, or never logged).
String _formatLastTime(LoggedSet? previous) {
  final parts = <String>[
    if (previous?.actualWeightKg != null)
      '${_trimWeight(previous!.actualWeightKg!)}kg',
    if (previous?.actualReps != null) '× ${previous!.actualReps}',
  ];
  return parts.isEmpty ? 'First time' : parts.join(' ');
}

/// "60kg × 8" for a set's OWN actuals — omits either half when unset, "—"
/// when neither was recorded. Distinct from [_formatLastTime]'s "First
/// time": that means "no prior performance to compare against"; this means
/// "nothing was typed on this set itself" (the review list's skipped-with-
/// nothing-typed case).
String _formatSetActuals(LoggedSet set) {
  final parts = <String>[
    if (set.actualWeightKg != null) '${_trimWeight(set.actualWeightKg!)}kg',
    if (set.actualReps != null) '× ${set.actualReps}',
  ];
  return parts.isEmpty ? '—' : parts.join(' ');
}

/// The Undo snackbar's "what just got logged" line — reads naturally for
/// every combination a set can actually have (weight+reps, reps-only for a
/// bodyweight movement, or neither for a bare AMRAP tap), unlike
/// [_formatSetActuals]'s table-cell "×"/"—" shorthand which the review list
/// wants but a sentence doesn't.
String _doneSnackbarSummary(LoggedSet set) {
  final weight = set.actualWeightKg;
  final reps = set.actualReps;
  if (weight != null && reps != null) {
    return '${_trimWeight(weight)}kg × $reps logged';
  }
  if (reps != null) return '$reps rep${reps == 1 ? '' : 's'} logged';
  if (weight != null) return '${_trimWeight(weight)}kg logged';
  return 'Set logged';
}

/// Whole seconds remaining until [d] elapses, rounded up so a countdown
/// never flashes "0" a moment before it's actually over; clamped at 0 for an
/// already-elapsed duration.
int _ceilSeconds(Duration d) =>
    d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();

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
  BoxShadow(
    color: color.withValues(alpha: 0.08),
    blurRadius: 24,
    spreadRadius: -6,
    offset: const Offset(0, 8),
  ),
];

// ---- Small building blocks ----------------------------------------------

/// One exercise's card in the end-of-workout review — its name plus every
/// resolved (done or skipped) set, each tappable to fix before Finish.
class _ReviewExerciseGroup extends StatelessWidget {
  const _ReviewExerciseGroup({required this.exercise, required this.onEditSet});

  final SessionExercise exercise;
  final void Function(LoggedSet set, int position) onEditSet;

  @override
  Widget build(BuildContext context) {
    final resolved = <(int, LoggedSet)>[];
    for (final (i, set) in exercise.sets.indexed) {
      if (!set.pending) resolved.add((i + 1, set));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name,
            style: AppText.rowTitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          for (final (position, set) in resolved)
            _ReviewSetRow(
              position: position,
              set: set,
              onTap: () => onEditSet(set, position),
            ),
        ],
      ),
    );
  }
}

/// One reviewable set row — flags a skip distinctly (muted dash icon, "Skipped"
/// label) from a done set (Pulse check, its actual reps/weight). The whole row
/// is the tap target, opening [_SetReviewSheet] either way.
class _ReviewSetRow extends StatelessWidget {
  const _ReviewSetRow({
    required this.position,
    required this.set,
    required this.onTap,
  });

  final int position;
  final LoggedSet set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skipped = set.skipped;
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                skipped
                    ? Icons.remove_circle_outline_rounded
                    : Icons.check_circle_rounded,
                size: 16,
                color: skipped ? AppColors.ink3 : AppColors.pulse,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set $position',
                  style: AppText.body.copyWith(
                    fontSize: 14,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              Text(
                skipped ? 'Skipped' : _formatSetActuals(set),
                style: AppText.meta.copyWith(
                  color: skipped ? AppColors.ink3 : AppColors.ink2,
                  fontWeight: skipped ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The review-edit sheet: lets the reviewer type real reps/weight for a
/// skipped set ("Mark done") or correct an already-logged one ("Save").
/// Pops `(reps, weight)` on save, `null` on dismiss/cancel — mirrors the
/// running screen's own reps/weight inputs ([_StepperField]) so editing here
/// feels like the same control, not a different one.
class _SetReviewSheet extends StatefulWidget {
  const _SetReviewSheet({
    required this.title,
    required this.wasSkipped,
    this.initialReps,
    this.initialWeight,
  });

  final String title;
  final bool wasSkipped;
  final int? initialReps;
  final double? initialWeight;

  @override
  State<_SetReviewSheet> createState() => _SetReviewSheetState();
}

class _SetReviewSheetState extends State<_SetReviewSheet> {
  late final TextEditingController _reps = TextEditingController(
    text: widget.initialReps?.toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: widget.initialWeight != null
        ? _trimWeight(widget.initialWeight!)
        : '',
  );

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _save() {
    final reps = int.tryParse(_reps.text.trim());
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop((reps, weight));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: AppText.cardTitle.copyWith(
              fontSize: 18,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.wasSkipped
                ? 'Enter what you actually did to mark this done.'
                : 'Correct the reps or weight actually logged.',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _StepperField(
                label: 'Reps',
                controller: _reps,
                step: 1,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(width: AppSpacing.m),
              _StepperField(
                label: 'Weight (kg)',
                controller: _weight,
                step: 2.5,
                hint: '—',
                onChanged: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 20),
          PillButton(
            label: widget.wasSkipped ? 'Mark done' : 'Save',
            icon: Icons.check_rounded,
            enabled: true,
            onTap: _save,
          ),
        ],
      ),
    );
  }
}

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
  const _Eyebrow(this.text, {required this.color, this.icon});

  final String text;
  final Color color;

  /// An optional mark inside the chip — the phase's identity at a glance
  /// (flame for warm-up, pause for rest, check for complete).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: AppText.meta.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
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

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.value,
  );

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
  const _ElapsedLabel({
    required this.elapsed,
    required this.isPaused,
    required this.onTogglePause,
  });

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
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
    this.intraSessionDeltaLabel,
  });

  final String lastTimeLabel;
  final ProgressionGoal goal;
  final String? targetText;

  /// Today's in-progress verdict against [lastTimeLabel] (see
  /// [compareToLastTime]) — null whenever there's nothing real to compare
  /// yet (first time ever, or no rep count typed in), in which case no
  /// badge shows at all.
  final SetProgressComparison? comparison;

  /// "+2.5kg from your previous set" — this session's own previous set in
  /// the same exercise, distinct from [comparison]'s cross-session verdict.
  /// Null when there's no previous set yet or nothing changed.
  final String? intraSessionDeltaLabel;

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
          if (comparison != null)
            _ProgressVerdictBadge(comparison: comparison!),
          if (intraSessionDeltaLabel != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 13,
                  color: AppColors.ember,
                ),
                const SizedBox(width: 4),
                Text(
                  intraSessionDeltaLabel!,
                  key: const Key('intra-session-delta'),
                  style: AppText.meta.copyWith(
                    color: AppColors.ember,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (targetText != null) ...[
            const SizedBox(height: 2),
            Text(
              'Target: $targetText',
              style: AppText.meta.copyWith(
                color: AppColors.ink3,
                fontWeight: FontWeight.w400,
              ),
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

/// The workout's now-playing companion, pinned to the top-of-logging slot
/// (`StaggeredReveal(index: 0)`) — renders on every working set, so unlike
/// [_RestPhase] it never degrades to nothing: connected+playing shows
/// [_NowPlayingCard], anything else (disconnected, connecting, nothing
/// loaded) shows [_ConnectMusicChip]. That keeps "don't hide music
/// mid-workout" true without nagging elsewhere — the rest-phase slot below
/// keeps the old graceful degrade instead.
///
/// "Change the song" here is next/previous only (`MusicController.next`/
/// `previous`, wired to App Remote's `skipNext`/`skipPrevious`) — there's no
/// browse/search picker. Spotify's App Remote doesn't expose one either
/// without building real Web API search UI, which is a materially bigger
/// feature than this pass.
class _SessionNowPlaying extends StatelessWidget {
  const _SessionNowPlaying({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connSnap) {
        if (connSnap.data != MusicConnection.connected) {
          return _ConnectMusicChip(controller: controller);
        }
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            if (playing == null) {
              return _ConnectMusicChip(controller: controller);
            }
            return _NowPlayingCard(controller: controller, playing: playing);
          },
        );
      },
    );
  }
}

/// Composes [ring] with [_NowPlayingCard] as one cohesive unit — song on
/// top, rest ring below — whenever [controller] is connected and something's
/// loaded. Falls back to exactly `Center(child: ring)` otherwise (no
/// controller, disconnected, or nothing playing), so a rest phase with no
/// music present is pixel-identical to before this existed — never an empty
/// gap where the song card would have been, and never a connect chip
/// (unlike [_SessionNowPlaying]'s slot, this screen is Spacer-balanced
/// around the ring).
class _RestPhase extends StatelessWidget {
  const _RestPhase({required this.ring, required this.controller});

  final Widget ring;
  final MusicController? controller;

  @override
  Widget build(BuildContext context) {
    final music = controller;
    if (music == null) return Center(child: ring);
    return StreamBuilder<MusicConnection>(
      stream: music.connection,
      initialData: music.currentConnection,
      builder: (context, connSnap) {
        // Rest is the right place for music — hands are free, attention is.
        // Disconnected: one calm invite (never a nag — it vanishes once
        // connected). Connected: the now-playing card rides above the ring.
        if (connSnap.data != MusicConnection.connected) {
          return Column(
            children: [
              _ConnectMusicChip(controller: music),
              const SizedBox(height: 18),
              Center(child: ring),
            ],
          );
        }
        return StreamBuilder<NowPlaying?>(
          stream: music.nowPlaying,
          initialData: music.currentNowPlaying,
          builder: (context, nowSnap) {
            final playing = nowSnap.data;
            if (playing == null) return Center(child: ring);
            return Column(
              children: [
                _NowPlayingCard(controller: music, playing: playing),
                const SizedBox(height: 16),
                Center(child: ring),
              ],
            );
          },
        );
      },
    );
  }
}

/// The actual now-playing card — shared by [_SessionNowPlaying] (standalone,
/// top of the running screen) and [_RestPhase] (composed above the rest
/// ring). The card itself (everything but the prev/pause/next buttons,
/// which keep their own taps via their own `InkWell`) opens
/// [MusicPlayerPage] — nested `InkWell`s resolve taps to whichever one sits
/// directly under the finger, so no manual hit-test carve-out is needed.
///
/// Adaptive, Spotify-style: the card's tint is extracted from the track's
/// own artwork ([PaletteGenerator] over the bytes, async + cached per
/// track), so the session surface takes on each song's visual identity —
/// falling back to the pulse-accented neutral until artwork resolves.
class _NowPlayingCard extends StatefulWidget {
  const _NowPlayingCard({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  State<_NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<_NowPlayingCard> {
  static String? _cachedKey;
  static Color? _cachedAccent;

  Color? _accent;

  @override
  void initState() {
    super.initState();
    _accent = _cachedKey == _keyOf(widget.playing) ? _cachedAccent : null;
    _extractAccent();
  }

  @override
  void didUpdateWidget(covariant _NowPlayingCard old) {
    super.didUpdateWidget(old);
    if (_keyOf(old.playing) != _keyOf(widget.playing)) _extractAccent();
  }

  String _keyOf(NowPlaying p) => '${p.title}|${p.artist}';

  Future<void> _extractAccent() async {
    final bytes = widget.playing.artworkBytes;
    final key = _keyOf(widget.playing);
    if (bytes == null || bytes.isEmpty) return;
    if (_cachedKey == key && _cachedAccent != null) {
      if (mounted) setState(() => _accent = _cachedAccent);
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(120, 120),
      );
      // Prefer a vibrant swatch; fall back to the dominant color. Darkened
      // toward the card's own brightness so text always stays readable.
      Color? chosen =
          palette.vibrantColor?.color ?? palette.dominantColor?.color;
      chosen ??= palette.colors.isEmpty ? null : palette.colors.first;
      if (chosen == null || !mounted) return;
      final tinted = Color.lerp(chosen, AppColors.ground, 0.45)!;
      _cachedKey = key;
      _cachedAccent = tinted;
      setState(() => _accent = tinted);
    } catch (_) {
      // Artwork failed to decode — the neutral fallback below is fine.
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MusicPlayerPage(controller: widget.controller),
            fullscreenDialog: true,
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent == null
              ? AppColors.surfaceRaised
              // The track's own color, pulled most of the way to the
              // card's brightness — identity without glare.
              : Color.lerp(AppColors.surfaceRaised, accent, 0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (accent ?? AppColors.pulse).withValues(alpha: 0.22),
          ),
          boxShadow: accent == null
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          children: [
            MusicArtwork(
              bytes: widget.playing.artworkBytes,
              url: widget.playing.artworkUrl,
              size: 40,
              iconSize: 18,
              borderRadius: 10,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.playing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    widget.playing.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(
                      fontSize: 11.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            _MusicIconButton(
              icon: Icons.skip_previous_rounded,
              onTap: widget.controller.previous,
            ),
            _MusicIconButton(
              icon: widget.playing.isPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              onTap: () => widget.playing.isPaused
                  ? widget.controller.play()
                  : widget.controller.pause(),
              primary: true,
            ),
            _MusicIconButton(
              icon: Icons.skip_next_rounded,
              onTap: widget.controller.next,
            ),
          ],
        ),
      ),
    );
  }
}

/// One prev/play-pause/next control in [_NowPlayingCard] — deliberately
/// small (this card is a companion, not the primary content) but still a
/// real tap target via [IconButton]'s built-in min-size.
class _MusicIconButton extends StatelessWidget {
  const _MusicIconButton({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final Future<void> Function() onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: IconButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        icon: Icon(icon, size: primary ? 22 : 18),
        color: primary ? AppColors.pulse : AppColors.ink2,
        splashRadius: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

/// The logging slot's fallback when there's no [_NowPlayingCard] to show
/// (disconnected, connecting, or connected with nothing loaded) — a small
/// always-reachable way into [MusicPlayerPage]'s connect flow, so this slot
/// never goes fully blank the way [_RestPhase] does. Generic Lucide glyph,
/// deliberately no brand mark here — the Spotify logo appears in exactly
/// one place (Settings' MUSIC row).
class _ConnectMusicChip extends StatelessWidget {
  const _ConnectMusicChip({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MusicPlayerPage(controller: controller),
              fullscreenDialog: true,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.music, size: 14, color: AppColors.ink2),
              const SizedBox(width: 6),
              Text(
                'Connect Music',
                style: AppText.meta.copyWith(color: AppColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestAdjustButton extends StatelessWidget {
  const _RestAdjustButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;

  /// An optional mark beside the label (±) — the button reads as an
  /// adjustment, not just a word.
  final IconData? icon;

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
            color: AppColors.surfaceRaised.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.ink3),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: AppText.button.copyWith(
                  fontSize: 15,
                  color: AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom action zone as one coherent unit rather than floating
/// buttons: a hairline top border separates it from the content above,
/// [onBack] (only when there's something to walk back to) sits centered
/// above the primary row, and Skip/Done keep their established hierarchy —
/// Skip small and muted, Done unmistakably primary.
class _ActionCluster extends StatelessWidget {
  const _ActionCluster({
    required this.onSkip,
    required this.onDone,
    this.onBack,
  });

  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.m),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onBack != null) ...[
            _BackControl(onTap: onBack!),
            const SizedBox(height: AppSpacing.s),
          ],
          Row(
            children: [
              // Deliberately smaller and visually muted next to Done — Skip
              // is the exception path, Done is the expected one; an
              // accidental tap should default toward the common case.
              Expanded(
                child: PillButton(
                  label: 'Skip',
                  icon: Icons.skip_next_rounded,
                  color: AppColors.surfaceRaised,
                  textColor: AppColors.ink2,
                  enabled: true,
                  onTap: onSkip,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                flex: 2,
                child: PillButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  enabled: true,
                  onTap: onDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "walk back one set" control shown above Skip/Done once there's
/// something to walk back to (see [LiveSession.previousResolvedSet]).
/// Deliberately smaller and quieter than either — a rarely-needed recovery
/// action, not a step in the normal flow — so it never competes with Done.
class _BackControl extends StatelessWidget {
  const _BackControl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_back_rounded,
                size: 15,
                color: AppColors.ink3,
              ),
              const SizedBox(width: 6),
              Text('Back', style: AppText.meta.copyWith(color: AppColors.ink3)),
            ],
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

class _StepperFieldState extends State<_StepperField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _punch = AnimationController(
    vsync: this,
    value: 1,
  );

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
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
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
    // One bordered pill housing minus/value/plus — a single tactile unit
    // with hairline dividers marking its three regions, rather than three
    // separate floating chips with gaps between them.
    final radius = BorderRadius.circular(AppRadius.chip + 6);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: AppText.meta.copyWith(
              color: AppColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: radius,
              border: Border.all(color: AppColors.hairline2),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Row(
                children: [
                  _StepButton(
                    icon: Icons.remove_rounded,
                    onTap: () => _step(-widget.step),
                  ),
                  Container(width: 1, color: AppColors.hairline2),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _punch,
                      builder: (context, child) =>
                          Transform.scale(scale: _punch.value, child: child),
                      child: TextField(
                        controller: widget.controller,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        cursorColor: AppColors.ember,
                        style: AppText.rowTitle.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                        onChanged: (_) => widget.onChanged(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.hint,
                          hintStyle: AppText.rowTitle.copyWith(
                            color: AppColors.ink3,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 4,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, color: AppColors.hairline2),
                  _StepButton(
                    icon: Icons.add_rounded,
                    onTap: () => _step(widget.step),
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

/// One ± segment of a [_StepperField]'s pill — no background/border of its
/// own (the pill's outer [Container] owns those; [ClipRRect] keeps the ink
/// response inside the shared shape), just a clear tap target with an
/// ember-tinted splash/highlight for a tactile press state.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.ember.withValues(alpha: 0.18),
          highlightColor: AppColors.ember.withValues(alpha: 0.10),
          child: SizedBox(
            width: 46,
            height: 52,
            child: Center(child: Icon(icon, size: 18, color: AppColors.ink2)),
          ),
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
  late final AnimationController _scale = AnimationController(
    vsync: this,
    value: 1,
  );

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
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
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
            Text(
              label,
              style: AppText.meta.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
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

class _SetChipState extends State<_SetChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this,
    value: _targetScale(widget.state),
  );

  double _targetScale(_ChipState state) =>
      state == _ChipState.current ? 1.1 : 1.0;

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
    final spring = widget.state == _ChipState.done
        ? AppSprings.bounce
        : AppSprings.standard;
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
                color: state == _ChipState.current
                    ? Colors.white
                    : AppColors.ink3,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final popped = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
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

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
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
  late final AnimationController _correction = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  double? _lastProgress;

  double get _trueProgress {
    final totalMs = widget.total * 1000;
    return totalMs <= 0
        ? 0.0
        : (widget.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
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
              final progress = (_trueProgress + _correction.value).clamp(
                0.0,
                1.0,
              );
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

  static final _wholeStyle = AppText.heroNumber.copyWith(
    fontSize: 50,
    color: AppColors.ink,
  );
  static final _centisStyle = AppText.heroNumber.copyWith(
    fontSize: 26,
    color: AppColors.ink2,
  );

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
            child: Text(
              time.whole,
              key: const Key('rest-time-whole'),
              style: _wholeStyle,
            ),
          ),
          _FixedSlot(
            reference: '.99',
            alignment: Alignment.centerLeft,
            style: _centisStyle,
            child: Text(
              time.centis,
              key: const Key('rest-time-centis'),
              style: _centisStyle,
            ),
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
      ..color = AppColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // A soft halo under the sweep — the ring's "alive" breathing reads as
    // light, not just a thicker stroke.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      Paint()
        ..color = AppColors.ink2.withValues(alpha: 0.10 + 0.10 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22 + 4 * glow
        ..strokeCap = StrokeCap.round,
    );

    // The sweep itself: a warm ivory gradient (brighter at the leading
    // cap) so the ring reads as lit rather than flat.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi * clamped,
          colors: [AppColors.ink2.withValues(alpha: 0.70), AppColors.ink],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11 + 1.5 * glow
        ..strokeCap = StrokeCap.round,
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 0,
  );
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
      builder: (context, child) =>
          Transform.scale(scale: _controller.value, child: child),
      child: widget.child,
    );
  }
}
