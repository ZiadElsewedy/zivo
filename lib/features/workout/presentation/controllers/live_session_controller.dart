import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/util/parse.dart';
import '../../domain/exercise_history.dart';
import '../../domain/live_session.dart';
import '../../domain/live_session_to_workout_log.dart';
import '../../domain/logged_set.dart';
import '../../domain/progression.dart';
import '../../domain/rest_policy.dart';
import '../../domain/session_exercise.dart';
import '../../domain/set_outcome.dart';
import '../../domain/set_type.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_repository.dart';
import '../../domain/workout_repository.dart';
import '../../domain/workout_session_repository.dart';
import '../widgets/live_session/live_session_format.dart';

/// Whole seconds remaining until [d] elapses, rounded up so a countdown never
/// flashes "0" a moment before it's actually over; clamped at 0 for an
/// already-elapsed duration.
int ceilSeconds(Duration d) =>
    d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();

/// The pre-workout warm-up phase's fixed default length — 5:00, chosen as a
/// reasonable one-size loosen-up window; configurable later, not now.
const int warmupSeconds = 300;

/// Everything the live session *is*, with none of what it looks like.
///
/// This was ~870 lines inside `_LiveSessionPageState`: three independent
/// clocks (rest, warm-up, elapsed), a debounced draft autosave, a
/// `SharedPreferences` countdown that survives an app kill, a history
/// subscription, the set-resolution state machine, and pause/finish/leave/
/// discard. All of it reachable only by pumping a widget.
///
/// Pulling it into a [ChangeNotifier] buys three things:
///
/// - **The rules become testable directly.** "A rest that expired while the
///   app was backgrounded advances the set on resume" is a statement about
///   this class; it needed a `WidgetTester` and a fake clock to assert before.
/// - **The page can only render.** `build` reads getters and calls commands;
///   there is no longer a way to write session state from inside a widget.
/// - **The three clocks stop being able to disagree.** They shared mutable
///   fields with the build method, so "is a rest running" was answerable from
///   two places. Now [restRemaining] is the only answer.
///
/// It is deliberately a plain [ChangeNotifier] — see `AGENTS.md`: no
/// state-management package enters this codebase without an ADR, and the
/// existing `LocaleController`/`MusicController` already establish the shape.
///
/// **Navigation is not its job.** [finish], [leave] and [discard] do the
/// writes and return; the page pops. A controller that could pop would be
/// back to knowing about widgets.
class LiveSessionController extends ChangeNotifier {
  LiveSessionController({
    required this.day,
    required WorkoutPlan plan,
    required WorkoutSessionRepository sessions,
    required TickerProvider vsync,
    required this.now,
    LiveSession? resume,
  }) : _plan = plan,
       // An initializing formal would have to be `this._sessions`, and a
       // named parameter cannot start with an underscore — so these stay
       // plain assignments.
       // ignore: prefer_initializing_formals
       _sessions = sessions,
       // ignore: prefer_initializing_formals
       _vsync = vsync,
       _resumed = resume != null {
    _session =
        resume ??
        LiveSession.start(
          day,
          id: now().microsecondsSinceEpoch.toString(),
          planId: plan.id,
          now: now(),
        );
  }

  /// The day being run (a snapshot embedded in the session).
  final WorkoutDay day;

  /// The clock this session runs on — real wall time in production, injected
  /// in tests so the countdown maths is deterministic.
  final DateTime Function() now;

  final WorkoutPlan _plan;
  final WorkoutSessionRepository _sessions;
  final TickerProvider _vsync;
  final bool _resumed;

  late LiveSession _session;
  bool _disposed = false;

  /// The current set's reps/weight inputs. The controller owns them because
  /// it is what reads them ([setDone], [_saveDraft]) and what writes them
  /// ([_prefillInputs]); the page only hands them to a field.
  final TextEditingController reps = TextEditingController();
  final TextEditingController weight = TextEditingController();

  /// Drives the rest countdown at frame rate (~60fps) rather than once a
  /// second. Every tick is just a notify; the displayed value is always
  /// recomputed fresh from [_restEndsAt] against [now], never accumulated
  /// from the ticker's own elapsed time, so it stays wall-clock-correct
  /// through pause/resume/adjust.
  Ticker? _restTicker;
  int? _restTotalSeconds;

  /// The warm-up's own ticker — a distinct one-shot phase shown before the
  /// first set of a genuinely fresh session.
  Ticker? _warmupTicker;
  int? _warmupTotalSeconds;

  /// Debounces typed-but-not-done actuals into an autosaved draft.
  Timer? _draftDebounce;

  /// The absolute wall-clock moment rest ends — the single source of truth
  /// [restRemaining] reads every frame (and on app resume, so a suspended
  /// app snaps back to the real remaining time instead of resuming from
  /// wherever it froze). Null while paused (frozen into
  /// [_pausedRestRemaining] instead) and whenever no rest is running.
  DateTime? _restEndsAt;
  Duration? _pausedRestRemaining;
  DateTime? _warmupEndsAt;
  Duration? _pausedWarmupRemaining;

  /// Ticks the "time in workout" label once a second. Not running while
  /// paused or once the session completes.
  Timer? _elapsedTimer;

  StreamSubscription<List<LiveSession>>? _pastSessionsSub;
  List<LiveSession> _pastSessions = const [];

  /// Whether the current set's actuals reflect real user input (or an
  /// already-saved draft) rather than an untouched suggestion — [_saveDraft]
  /// must never write a suggestion the user never looked at into the session
  /// as if it were typed.
  bool _actualsTouched = false;

  /// The first real history snapshot arrives asynchronously, so the initial
  /// prefill runs before [_pastSessions] is populated. Re-running it once,
  /// the moment real history lands, keeps the prefilled reps/weight in sync
  /// with what the Goal block ends up showing.
  bool _prefillRefreshedFromHistory = false;

  bool _busy = false;
  bool _resolvingSet = false;

  // ---- Reads ---------------------------------------------------------------

  LiveSession get session => _session;
  List<LiveSession> get pastSessions => _pastSessions;
  int? get restTotalSeconds => _restTotalSeconds;
  int? get warmupTotalSeconds => _warmupTotalSeconds;

  /// Guards [finish]/[leave]/[discard] against re-entrancy — all are async
  /// and otherwise callable again (double-tap, or Finish racing the close
  /// button) before the first call's writes and pop land.
  bool get isBusy => _busy;

  /// True through the brief "completion beat" hold in
  /// [_afterResolvingCurrentSet]. Done/Skip stay on screen through the hold,
  /// so this guards them against a tap resolving a set that is already
  /// mid-resolution.
  bool get isResolvingSet => _resolvingSet;

  /// The live rest countdown — frozen at the paused remainder while paused,
  /// otherwise the wall-clock gap to [_restEndsAt] (never negative). Null
  /// whenever no rest is running, which doubles as "are we resting".
  Duration? get restRemaining {
    final paused = _pausedRestRemaining;
    if (paused != null) return paused;
    final endsAt = _restEndsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// The warm-up countdown — same shape as [restRemaining], and doubles as
  /// "is the warm-up phase showing".
  Duration? get warmupRemaining {
    final paused = _pausedWarmupRemaining;
    if (paused != null) return paused;
    final endsAt = _warmupEndsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  ExerciseHistory? historyFor(SessionExercise exercise) =>
      lastPerformanceFor(exercise.exerciseId, _pastSessions);

  /// The matching set from the last time this exercise was trained —
  /// index-aligned against that history's *working* sets only.
  LoggedSet? previousSetFor(SessionExercise exercise, LoggedSet set) {
    if (set.type != SetType.working) return null;
    final history = historyFor(exercise);
    if (history == null) return null;
    final workingHistory = history.sets
        .where((s) => s.type == SetType.working)
        .toList(growable: false);
    final index = workingSetIndexOf(exercise, set);
    if (index < 0 || index >= workingHistory.length) return null;
    return workingHistory[index];
  }

  /// The most recently COMPLETED set before [set] within [exercise], THIS
  /// session — distinct from [previousSetFor], which reaches back to a past
  /// session. Null for the exercise's first set, or when nothing before it
  /// has been completed (a skip doesn't count: it carries no actuals).
  LoggedSet? previousSetInSession(SessionExercise exercise, LoggedSet set) {
    LoggedSet? prev;
    for (final s in exercise.sets) {
      if (s.id == set.id) break;
      if (s.done) prev = s;
    }
    return prev;
  }

  /// **The load you are already lifting** — what this exercise was last
  /// actually done at, so the weight field arrives filled in instead of empty.
  ///
  /// [computeGoal] only suggests a weight when it has an *index-aligned* set
  /// from the last time this exercise was trained, or a `targetWeightKg` on
  /// the plan. Neither holds for the common case of a plan written without
  /// loads: set 1 gets typed, and then set 2 — and every set after it, and the
  /// same exercise next week — asks for the number again from scratch. The
  /// weight barely changes between sets, so re-typing it is pure toil, and an
  /// empty field is the reason sets end up logged with no load at all.
  ///
  /// Searched nearest-first, because nearer evidence is better evidence:
  ///
  /// 1. an earlier set of this exercise **in this session** (a typed draft
  ///    counts — it's what you're lifting right now),
  /// 2. the index-aligned set from the last time it was trained,
  /// 3. the last set of that session that carried a load at all — index
  ///    alignment fails as soon as a set is added or dropped, and last week's
  ///    load is still the right guess when it does,
  /// 4. whatever the plan prescribed.
  ///
  /// Scoped to the SAME exercise throughout: carrying a curl's load onto a
  /// press would be worse than leaving the field blank. Null means there is
  /// genuinely nothing to go on (a bodyweight movement never logged with a
  /// load), and the field stays empty — as it should.
  double? carriedWeightFor(SessionExercise exercise, LoggedSet set) {
    double? inSession;
    for (final s in exercise.sets) {
      if (s.id == set.id) break;
      if (s.actualWeightKg != null) inSession = s.actualWeightKg;
    }
    if (inSession != null) return inSession;

    final aligned = previousSetFor(exercise, set)?.actualWeightKg;
    if (aligned != null) return aligned;

    final history = historyFor(exercise);
    if (history != null) {
      for (final s in history.sets.reversed) {
        if (s.actualWeightKg != null) return s.actualWeightKg;
      }
    }
    return set.targetWeightKg;
  }

  // ---- Lifecycle -----------------------------------------------------------

  /// Starts the session: settles an empty day straight into "completed",
  /// arms the elapsed clock, opens the warm-up phase for a genuinely fresh
  /// start, restores any rest that was running when the app was killed, and
  /// subscribes to history.
  ///
  /// Separate from the constructor because it subscribes and touches
  /// platform channels — a constructor that did that could not be used to
  /// build a controller in a test without also starting its clocks.
  void start() {
    if (_session.currentSet == null) {
      // Nothing to do (an empty day) — settle straight into completed.
      _session = _session.complete(now: now());
    }
    if (!_session.isComplete && !_session.isPaused) {
      _startElapsedTimer();
    }
    // Only a genuinely fresh start opens on the warm-up phase — a resumed
    // session (even one with nothing logged) or one that already has a done
    // set skips straight to running, since re-showing it wouldn't mean
    // "before your first set" any more.
    if (!_resumed && _session.completedSetCount == 0 && !_session.isComplete) {
      _startWarmup();
    }
    unawaited(_restorePersistedRest());
    _prefillInputs();

    _pastSessionsSub = _sessions.watchAll().listen((sessions) {
      if (_disposed) return;
      // §3.2 invariant 4: a split's history is its own — scoped to THIS
      // session's split (splitId == planId), never another split's, even when
      // they happen to share an exerciseId. Without the planId filter,
      // "previous performance" could silently show another split's numbers.
      _pastSessions = sessions
          .where((s) => s.id != _session.id && s.planId == _session.planId)
          .toList(growable: false);
      notifyListeners();
      if (!_prefillRefreshedFromHistory) {
        _prefillRefreshedFromHistory = true;
        _prefillInputs();
      }
    });
    unawaited(_sessions.saveSession(_session));
  }

  /// The OS suspends `Timer`s and `Ticker`s while backgrounded, so a plain
  /// tick-counter would resume from wherever it froze. Both clocks resync
  /// from their wall-clock sources of truth instead. Both no-op on their own
  /// while the session is explicitly paused, so backgrounding while paused
  /// can't sneak the clock back to life.
  void onAppResumed() {
    _resyncRestOnResume();
    _resyncWarmupOnResume();
    _tickElapsed();
  }

  @override
  void dispose() {
    _disposed = true;
    _restTicker?.dispose();
    _warmupTicker?.dispose();
    _elapsedTimer?.cancel();
    _draftDebounce?.cancel();
    unawaited(_pastSessionsSub?.cancel());
    reps.dispose();
    weight.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- Input prefill -------------------------------------------------------

  /// Seeds the reps/weight inputs — preferring a typed-but-not-done draft
  /// over any computed suggestion, so returning to a set shows what was
  /// actually typed, not a reset. A never-touched set seeds from the computed
  /// [ProgressionGoal]: the plan's own prescription when there's no history
  /// for this exact set, or the double-progression suggestion once there is.
  /// "AMRAP" (to-failure, no history) has no number to seed, so reps is left
  /// blank for the user.
  void _prefillInputs() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) {
      reps.text = '';
      weight.text = '';
      _actualsTouched = false;
      return;
    }
    if (set.actualReps != null || set.actualWeightKg != null) {
      reps.text = set.actualReps?.toString() ?? '';
      weight.text = set.actualWeightKg != null
          ? trimWeight(set.actualWeightKg!)
          : '';
      // A real, already-saved draft — not just an untouched suggestion.
      _actualsTouched = true;
      return;
    }
    _actualsTouched = false;
    final goal = computeGoal(
      target: set.target,
      targetWeightKg: set.targetWeightKg,
      previous: previousSetFor(exercise, set),
      muscleGroup: exercise.muscleGroup,
    );
    // Compared against the domain's own sentinel, not a translated string:
    // `computeGoal` returns the literal 'AMRAP' for a to-failure target, so
    // localizing this comparison would break it in every language but English.
    reps.text = goal.repsLabel == kAmrapLabel ? '' : goal.repsLabel;
    // The engine's suggestion first — it's a *decision* (progress the load,
    // hold it, ease it). Only when it has nothing to decide from does the
    // field fall back to carrying the last known load forward, which is a
    // guess, but a far better one than an empty box. Either way this is still
    // a suggestion, not a draft: `_actualsTouched` stays false, so nothing is
    // persisted until the user commits or edits the set.
    final suggested = goal.weightKg ?? carriedWeightFor(exercise, set);
    weight.text = suggested != null ? trimWeight(suggested) : '';
  }

  /// Wired to both actual-value fields: keeps the live progression delta
  /// reactive to every keystroke, and schedules the debounced draft save that
  /// makes typed input survive a leave or an app kill.
  void onActualChanged() {
    _actualsTouched = true;
    _notify();
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 450), _saveDraft);
  }

  /// Persists whatever's currently typed into the current set's actuals
  /// WITHOUT marking it done — the "never lose data" path. Called both from
  /// the debounce timer and synchronously from [leave], so a leave right
  /// after typing (before the debounce would have fired) still flushes.
  void _saveDraft() {
    _draftDebounce?.cancel();
    if (_disposed || !_actualsTouched) return;
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    final typedReps = parseWhole(reps.text);
    final typedWeight = parseDecimal(weight.text);
    if (typedReps == set.actualReps && typedWeight == set.actualWeightKg) {
      return;
    }
    _session = _session.updateSet(
      exercise.id,
      set.id,
      actualReps: typedReps,
      actualWeightKg: typedWeight,
    );
    _notify();
    unawaited(_sessions.saveSession(_session));
  }

  /// Writes reviewed actuals onto an already-resolved set — the end-of-
  /// workout review's edit path. Reviewing a set IS performing it, so the
  /// caller passes [outcome] to flip a skipped set back to completed.
  void updateSetActuals(
    String exerciseId,
    String setId, {
    required int? actualReps,
    required double? actualWeightKg,
    SetOutcome? outcome,
  }) {
    _session = _session.updateSet(
      exerciseId,
      setId,
      actualReps: actualReps,
      actualWeightKg: actualWeightKg,
      outcome: outcome,
    );
    _notify();
    unawaited(_sessions.saveSession(_session));
  }

  // ---- Set resolution ------------------------------------------------------

  /// Marks the current set done with whatever is typed, then advances.
  ///
  /// [reducedMotion] comes from the caller because it is a `MediaQuery`
  /// value — the one piece of this decision that genuinely belongs to the
  /// widget tree.
  void setDone({required bool reducedMotion}) {
    if (_resolvingSet) return;
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    HapticFeedback.lightImpact();
    _session = _session.markSetDone(
      exercise.id,
      set.id,
      actualReps: parseWhole(reps.text),
      actualWeightKg: parseDecimal(weight.text),
    );
    _notify();
    _afterResolvingCurrentSet(exercise.restSeconds, reducedMotion);
  }

  /// The Skip affordance — advances past the current set exactly like
  /// [setDone], but logs no volume. Deliberately preserves whatever is typed
  /// in the fields on the set itself (an abandoned draft the end-of-workout
  /// review can still surface) rather than reading them the way Done does.
  void setSkip({required bool reducedMotion}) {
    if (_resolvingSet) return;
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) return;
    HapticFeedback.lightImpact();
    _session = _session.markSetSkipped(exercise.id, set.id);
    _notify();
    _afterResolvingCurrentSet(exercise.restSeconds, reducedMotion);
  }

  /// Shared tail for [setDone]/[setSkip]: completes the session if that was
  /// the last pending set (else starts rest), autosaves, and refreshes the
  /// prefill for whatever is now current.
  ///
  /// The advance is held behind a brief beat (see [isResolvingSet]): the
  /// session has already updated by the time this runs, so the just-resolved
  /// chip is already re-rendering in its done state on this very frame — but
  /// without a hold, the phase advance below would fire in that SAME frame
  /// and the whole running screen would be cross-fading away before the
  /// chip's spring had any time to register. Skipped under reduced motion,
  /// where there is no spring to wait for.
  void _afterResolvingCurrentSet(int restSeconds, bool reducedMotion) {
    _resolvingSet = true;
    final completing = _session.currentSet == null;

    // When another rest follows, go STRAIGHT there — the session pointer has
    // already advanced, so a hold would render the *next* exercise for a beat
    // before rest crossfades in. One synchronous transition, one crossfade.
    // The completion beat below is kept only for the actual last set, where
    // the checkmark spring IS the moment worth holding for.
    if (!completing && restSeconds > 0 && !reducedMotion) {
      // The guard stays up through the phase crossfade — the outgoing running
      // screen's Done/Skip remain hit-testable while they fade, and a tap
      // landing there must not resolve the *next* set by accident.
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        _resolvingSet = false;
      });
      _prefillInputs();
      _startRest(restSeconds);
      unawaited(_sessions.saveSession(_session));
      return;
    }

    final hold = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
    Future<void>.delayed(hold, () {
      _resolvingSet = false;
      if (_disposed) return;
      if (_session.currentSet == null) {
        _session = _session.complete(now: now());
      }
      _notify();
      unawaited(_sessions.saveSession(_session));
      _prefillInputs();
      if (_session.isComplete) {
        _clearRest();
        _elapsedTimer?.cancel();
        _notify();
      } else {
        // Rest is the plan's own value (Edit Workout's per-exercise rest, or
        // its "Default rest" bulk value) — the session counts down what the
        // user actually set, not a computed guess.
        _startRest(restSeconds);
      }
    });
  }

  /// The Back control — walks back exactly one set: whichever
  /// [LiveSession.previousResolvedSet] currently is. Tapping repeatedly walks
  /// back further, one set at a time; anything beyond that is the
  /// end-of-workout review's job.
  void back() {
    // Guards against racing the pending delayed callback in
    // [_afterResolvingCurrentSet] — see [isResolvingSet].
    if (_resolvingSet) return;
    final prev = _session.previousResolvedSet;
    if (prev == null) return;
    undoOutcome(prev.$1, prev.$2.id);
  }

  /// The shared undo primitive behind the Back control: clears [setId]'s
  /// outcome back to pending. If resolving that set was what completed the
  /// session, un-completes it too (status back to active, elapsed timer
  /// restarted) — an undo must be able to reverse the very last set of a
  /// workout, not just ones mid-flow.
  void undoOutcome(String exerciseId, String setId) {
    if (_disposed) return;
    HapticFeedback.selectionClick();
    final wasComplete = _session.isComplete;
    _session = _session.clearOutcome(exerciseId, setId);
    if (wasComplete) _session = _session.reopen();
    _notify();
    unawaited(_sessions.saveSession(_session));
    // Whatever rest/warm-up phase the resolved action kicked off no longer
    // applies to a set that's pending again — drop it and land back on the
    // running screen for that set.
    _clearRest();
    _pausedRestRemaining = null;
    if (wasComplete && !_session.isPaused) {
      _elapsedTimer ??= _newElapsedTimer();
    }
    _prefillInputs();
  }

  // ---- Rest ----------------------------------------------------------------

  /// Rest is a UI-side phase, so an app KILL while resting would otherwise
  /// drop the user back on the running screen with the countdown gone. The
  /// countdown's absolute wall-clock end is persisted (start/adjust/end/pause
  /// all maintain it) and restored on launch: still in the future → the phase
  /// resumes with the correct remaining time, exactly as if the app had never
  /// closed. Already past → silently skipped (the rest is simply over).
  static const _kRestEndsAt = 'zivo.session.rest.endsAtMs';
  static const _kRestTotal = 'zivo.session.rest.totalSeconds';

  Future<void> _persistRest() async {
    final prefs = await SharedPreferences.getInstance();
    final endsAt = _restEndsAt;
    final total = _restTotalSeconds;
    if (endsAt == null || total == null) {
      await prefs.remove(_kRestEndsAt);
      await prefs.remove(_kRestTotal);
      return;
    }
    await prefs.setInt(_kRestEndsAt, endsAt.millisecondsSinceEpoch);
    await prefs.setInt(_kRestTotal, total);
  }

  Future<void> _restorePersistedRest() async {
    if (_session.isComplete || _session.isPaused) return;
    if (_restEndsAt != null) return; // live rest already running
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kRestEndsAt);
    final total = prefs.getInt(_kRestTotal);
    if (ms == null || total == null || _disposed) return;
    final endsAt = DateTime.fromMillisecondsSinceEpoch(ms);
    if (!endsAt.isAfter(now())) {
      // The rest finished while the app was closed — clear it out.
      await prefs.remove(_kRestEndsAt);
      await prefs.remove(_kRestTotal);
      return;
    }
    _restEndsAt = endsAt;
    _restTotalSeconds = total;
    _notify();
    _restTicker?.dispose();
    _restTicker = _vsync.createTicker(_onRestTick)..start();
  }

  void _startRest(int seconds) {
    _restTicker?.dispose();
    _restTicker = null;
    if (seconds <= 0) {
      _restTotalSeconds = null;
      _restEndsAt = null;
      _notify();
      unawaited(_persistRest());
      return;
    }
    _restTotalSeconds = seconds;
    _restEndsAt = now().add(Duration(seconds: seconds));
    _notify();
    unawaited(_persistRest());
    _restTicker = _vsync.createTicker(_onRestTick)..start();
  }

  /// The rest ticker's per-frame callback — fires every rendered frame while
  /// resting, driving the sub-second countdown. Just a notify;
  /// [restRemaining] is what's displayed and is always recomputed fresh, so
  /// this can't drift the way summing per-tick deltas would.
  void _onRestTick(Duration elapsed) {
    if (_disposed) return;
    final remaining = restRemaining;
    if (remaining == null) return;
    if (remaining <= Duration.zero) {
      HapticFeedback.heavyImpact();
      // A short built-in platform chime — audible completion feedback for a
      // countdown the user may not be looking at, without pulling in an
      // audio-player dependency for one system sound.
      unawaited(SystemSound.play(SystemSoundType.alert));
      endRest();
      return;
    }
    _notify();
  }

  /// Resyncs the rest countdown on app resume — the OS suspends `Ticker`
  /// callbacks while backgrounded, so without this a rest that actually
  /// finished while away would sit frozen instead of advancing.
  void _resyncRestOnResume() {
    final remaining = restRemaining;
    if (_restEndsAt != null &&
        remaining != null &&
        remaining <= Duration.zero) {
      endRest();
    } else {
      _notify();
    }
  }

  /// Ends the rest phase — reached both by the countdown hitting zero and by
  /// the rest screen's "skip" tap.
  void endRest() {
    _clearRest();
    _notify();
  }

  void _clearRest() {
    _restTicker?.dispose();
    _restTicker = null;
    _restTotalSeconds = null;
    _restEndsAt = null;
    unawaited(_persistRest());
  }

  void adjustRest(int delta) {
    final endsAt = _restEndsAt;
    if (endsAt == null) return;
    HapticFeedback.selectionClick();
    final nextEndsAt = endsAt.add(Duration(seconds: delta));
    if (!nextEndsAt.isAfter(now())) {
      endRest();
      return;
    }
    _restEndsAt = nextEndsAt;
    // Keep the ring sensible: grow the total if the adjustment pushed the
    // remaining time past what it was counting down from.
    final remainingCeil = ceilSeconds(nextEndsAt.difference(now()));
    if (_restTotalSeconds != null && remainingCeil > _restTotalSeconds!) {
      _restTotalSeconds = remainingCeil;
    }
    _notify();
    unawaited(_persistRest());
  }

  // ---- Warm-up -------------------------------------------------------------

  /// Opens the one-shot pre-workout warm-up phase — the same
  /// wall-clock-endsAt approach as [_startRest], just fixed at
  /// [warmupSeconds] rather than a per-exercise rest window.
  void _startWarmup() {
    _warmupTicker?.dispose();
    _warmupTotalSeconds = warmupSeconds;
    _warmupEndsAt = now().add(const Duration(seconds: warmupSeconds));
    _warmupTicker = _vsync.createTicker(_onWarmupTick)..start();
  }

  void _onWarmupTick(Duration elapsed) {
    if (_disposed) return;
    final remaining = warmupRemaining;
    if (remaining == null) return;
    if (remaining <= Duration.zero) {
      HapticFeedback.heavyImpact();
      endWarmup();
      return;
    }
    _notify();
  }

  void _resyncWarmupOnResume() {
    final remaining = warmupRemaining;
    if (_warmupEndsAt != null &&
        remaining != null &&
        remaining <= Duration.zero) {
      endWarmup();
    } else {
      _notify();
    }
  }

  /// Ends the warm-up phase — reached both by the countdown hitting zero and
  /// by "Skip warm-up".
  void endWarmup() {
    _warmupTicker?.dispose();
    _warmupTicker = null;
    _warmupTotalSeconds = null;
    _warmupEndsAt = null;
    _notify();
  }

  void adjustWarmup(int delta) {
    final endsAt = _warmupEndsAt;
    if (endsAt == null) return;
    HapticFeedback.selectionClick();
    final nextEndsAt = endsAt.add(Duration(seconds: delta));
    if (!nextEndsAt.isAfter(now())) {
      endWarmup();
      return;
    }
    _warmupEndsAt = nextEndsAt;
    final remainingCeil = ceilSeconds(nextEndsAt.difference(now()));
    if (_warmupTotalSeconds != null && remainingCeil > _warmupTotalSeconds!) {
      _warmupTotalSeconds = remainingCeil;
    }
    _notify();
  }

  // ---- Elapsed clock -------------------------------------------------------

  Timer _newElapsedTimer() =>
      Timer.periodic(const Duration(seconds: 1), (_) => _tickElapsed());

  void _startElapsedTimer() => _elapsedTimer = _newElapsedTimer();

  /// Just a notify — the "time in workout" value itself is always read fresh
  /// from [LiveSession.activeElapsed]. A no-op (and self-cancelling) once the
  /// session completes or is paused.
  void _tickElapsed() {
    if (_disposed || _session.isComplete || _session.isPaused) {
      _elapsedTimer?.cancel();
      return;
    }
    _notify();
  }

  // ---- Pause / resume ------------------------------------------------------

  void togglePause() => _session.isPaused ? _resume() : _pause();

  /// Pauses the workout: stops the elapsed clock, and — if a countdown was
  /// actively running — freezes its remaining time rather than losing it.
  /// Model state ([LiveSession.pause]), so it is saved and survives
  /// leave/resume.
  void _pause() {
    final at = now();
    final endsAt = _restEndsAt;
    if (endsAt != null) {
      final remaining = endsAt.difference(at);
      _pausedRestRemaining = remaining.isNegative ? Duration.zero : remaining;
      _restTicker?.dispose();
      _restTicker = null;
      _restEndsAt = null;
    }
    final warmupEndsAt = _warmupEndsAt;
    if (warmupEndsAt != null) {
      final remaining = warmupEndsAt.difference(at);
      _pausedWarmupRemaining = remaining.isNegative ? Duration.zero : remaining;
      _warmupTicker?.dispose();
      _warmupTicker = null;
      _warmupEndsAt = null;
    }
    _session = _session.pause(now: at);
    _notify();
    _elapsedTimer?.cancel();
    // The persisted countdown must not resurrect a stale rest after a
    // pause → kill → relaunch; a paused rest lives only in memory.
    unawaited(_persistRest());
    unawaited(_sessions.saveSession(_session));
  }

  /// Resumes from [_pause]: restarts the elapsed clock, and — if a countdown
  /// was frozen — restores it from exactly where it left off.
  void _resume() {
    final at = now();
    final pausedRemaining = _pausedRestRemaining;
    if (pausedRemaining != null) {
      _pausedRestRemaining = null;
      _restEndsAt = at.add(pausedRemaining);
      _restTicker?.dispose();
      _restTicker = _vsync.createTicker(_onRestTick)..start();
      unawaited(_persistRest());
    }
    final pausedWarmupRemaining = _pausedWarmupRemaining;
    if (pausedWarmupRemaining != null) {
      _pausedWarmupRemaining = null;
      _warmupEndsAt = at.add(pausedWarmupRemaining);
      _warmupTicker?.dispose();
      _warmupTicker = _vsync.createTicker(_onWarmupTick)..start();
    }
    _session = _session.resume(now: at);
    _notify();
    unawaited(_sessions.saveSession(_session));
    _elapsedTimer?.cancel();
    _startElapsedTimer();
  }

  // ---- Exits ---------------------------------------------------------------

  /// FINISH: writes the workout log and advances the plan's cursor.
  ///
  /// Fires the Firestore writes without waiting: `.set()`/`.delete()` commit
  /// to the local cache (and any listener) immediately, cache-first — but the
  /// returned Future only resolves once the server acknowledges, so awaiting
  /// before popping would hang the button while offline.
  ///
  /// Returns false if a call was already in flight, so the caller knows not
  /// to pop twice.
  bool finish({
    required WorkoutRepository workouts,
    required WorkoutPlanRepository plans,
  }) {
    if (_busy) return false;
    _busy = true;
    _notify();
    unawaited(workouts.add(_session.toWorkoutLog()));
    // The recommendation advances past the day that was ACTUALLY trained —
    // any day is startable now, so the cursor can't blindly assume the
    // rotation's previous head was the one just completed.
    unawaited(
      plans.savePlan(_livePlan(plans).advanceToAfterDay(_session.dayId)),
    );
    unawaited(_sessions.saveSession(_session));
    return true;
  }

  /// The freshest known copy of the plan, looked up by id from the
  /// repository's live cache rather than trusting the snapshot captured when
  /// the page was pushed. That snapshot can go stale by the time a workout
  /// finishes — the plan may have been edited, reordered or re-imported
  /// mid-session — and [WorkoutPlanRepository.savePlan] writes the WHOLE
  /// `days` array back, so advancing the cursor on a stale snapshot would
  /// silently revert such an edit. Falls back to the snapshot if the plan is
  /// no longer among the saved splits (e.g. deleted mid-session).
  WorkoutPlan _livePlan(WorkoutPlanRepository plans) {
    for (final split in plans.splits) {
      if (split.id == _plan.id) return split;
    }
    return _plan;
  }

  /// LEAVE: the close (X) button and the system back gesture. The session
  /// autosaves as it is played, so leaving just pops — no confirmation,
  /// nothing deleted, the plan's cursor untouched. Flushes any pending
  /// debounced draft first, so a leave right after typing never loses it.
  ///
  /// The one exception: a session with zero logged sets AND no typed draft is
  /// indistinguishable from never having started one, so it is discarded
  /// silently rather than left behind as a "Resume" with nothing in it.
  ///
  /// `completedSetCount == 0` deliberately still reads as "empty" even when
  /// some sets were skipped: it never counts a skip, so a session where the
  /// user skipped several sets and completed none — nothing performed, no
  /// logged volume — is genuinely empty by the same standard as one nothing
  /// was touched on at all.
  bool leave() {
    if (_busy) return false;
    _saveDraft();
    _busy = true;
    _notify();
    _restTicker?.dispose();
    _restTicker = null;
    // Leaving drops the UI-side rest phase — clear its persisted countdown so
    // a later relaunch doesn't resurrect a stale one.
    unawaited(_persistRest());
    if (_session.completedSetCount == 0 && !_session.hasDraftActuals) {
      unawaited(_sessions.deleteSession(_session.id));
    }
    return true;
  }

  /// DISCARD: the explicit destructive action — erases the autosaved session
  /// entirely and leaves the plan's cursor untouched. The caller owns the
  /// confirmation prompt and the pop.
  bool discard() {
    if (_busy) return false;
    _busy = true;
    _notify();
    _restTicker?.dispose();
    _restTicker = null;
    // Fire-and-forget bookkeeping — a platform-channel future that must never
    // gate navigation.
    unawaited(_persistRest());
    unawaited(_sessions.deleteSession(_session.id));
    return true;
  }
}
