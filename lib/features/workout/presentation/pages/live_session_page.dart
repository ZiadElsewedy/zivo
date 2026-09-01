import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../domain/exercise_history.dart';
import '../../domain/live_session.dart';
import '../../domain/logged_set.dart';
import '../../domain/session_exercise.dart';
import '../../domain/set_outcome.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_session_repository.dart';
import '../../../music/music_config.dart';
import '../widgets/session_ambience.dart';
import '../../../../l10n/l10n.dart';
import '../controllers/live_session_controller.dart';
import '../widgets/live_session/phases/completed_phase.dart';
import '../widgets/live_session/phases/countdown_phase.dart';
import '../widgets/live_session/phases/running_phase.dart';
import '../widgets/live_session/live_session_format.dart';
import '../widgets/live_session/session_header.dart';
import '../widgets/live_session/session_review.dart';
import '../../../music/presentation/spotify_strip.dart';
import '../widgets/live_session/up_next_card.dart';

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
  /// Everything this screen *does* — the three clocks, the draft autosave,
  /// the set-resolution machine, the exits. See [LiveSessionController]; this
  /// State's only remaining jobs are to own the controller's lifetime, feed
  /// it the two things that genuinely belong to the widget tree (a
  /// [TickerProvider] and the reduced-motion flag), and pop.
  LiveSessionController? _controller;
  LiveSessionController get _c => _controller!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Built here rather than in [initState] because it needs the repository
    // from [AppScope], which is an inherited widget. This runs before the
    // first build, so nothing ever sees a null controller.
    if (_controller != null) return;
    _controller = LiveSessionController(
      day: widget.day,
      plan: widget.plan,
      sessions: AppScope.of(context).workoutSessions,
      vsync: this,
      now: widget.now,
      resume: widget.resume,
    )..addListener(_onControllerChanged);
    _c.start();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.onAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ---- Commands the page owns because they navigate ------------------------

  void _onSetDone() => _c.setDone(reducedMotion: reducedMotion(context));

  void _onSetSkip() => _c.setSkip(reducedMotion: reducedMotion(context));

  /// FINISH — the controller writes; this pops. It pops immediately rather
  /// than awaiting, because the writes are cache-first and awaiting them
  /// would hang the button while offline.
  void _onFinish() {
    if (!_c.finish(
      workouts: AppScope.of(context).workouts,
      plans: AppScope.of(context).workoutPlans,
    )) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// LEAVE — the close button and the system back gesture.
  void _onLeave() {
    if (!_c.leave()) return;
    Navigator.of(context).pop();
  }

  /// DISCARD — the explicit destructive action. The prompt lives here
  /// because a confirmation is a screen, not a rule.
  Future<void> _onDiscard() async {
    if (_c.isBusy) return;
    final confirmed = await confirmDestructive(
      context,
      title: l(context).liveDiscardTitle,
      body: l(context).liveDiscardBody,
      confirmLabel: l(context).liveDiscard,
      cancelLabel: l(context).liveKeepGoing,
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    if (!_c.discard()) return;
    navigator.pop();
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final musicController = kMusicEnabled
        ? AppScope.of(context).requireMusic
        : null;
    return PopScope(
      // The system/edge-swipe back gesture leaves like the close (X) button —
      // non-destructive, since the session already autosaves as it's played.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onLeave();
      },
      child: SessionAmbience(
        controller: musicController,
        child: Builder(
          builder: (context) {
            final accent = SessionAmbience.of(context);
            // The same swatch, normalised for foreground use — the strips'
            // transport controls draw with this one. Read HERE (inside the
            // ambience's own Builder) rather than deep in a phase builder:
            // those run against the State's context, which sits ABOVE
            // SessionAmbience and would resolve to null.
            final vivid = SessionAmbience.vividOf(context);
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: AnimatedContainer(
                // Each phase gets the one soft radial wash the handoff allows
                // it — ember from below while you're logging, green from the
                // middle while you rest. The music ambience still breathes
                // through it, but as a whisper (0.12) rather than the wash it
                // used to be: at full strength the track color simply replaced
                // the design's own tint.
                duration: reducedMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                decoration: BoxDecoration(gradient: _screenTint(accent)),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                        child: Column(
                          children: [
                            SessionHeader(
                              title: dayTitle(
                                context,
                                widget.day,
                              ).toUpperCase(),
                              elapsed: _c.session.isComplete
                                  ? _c.session.elapsed
                                  : _c.session.activeElapsed(now: widget.now()),
                              isPaused: _c.session.isPaused,
                              onClose: _onLeave,
                              onDiscard: _onDiscard,
                              onTogglePause: _c.session.isComplete
                                  ? null
                                  : _c.togglePause,
                            ),
                            const SizedBox(height: 20),
                            TrainSegmentBar(
                              total: _exerciseCount,
                              completed: _exercisesBehind,
                              current: _currentExerciseIndex,
                            ),
                            const SizedBox(height: 9),
                            TrainSegmentCaptions(
                              left: _exerciseCaption,
                              right: _tallyCaption,
                              rightColor: _c.restRemaining != null
                                  ? TrainColors.green.withValues(alpha: 0.75)
                                  : const Color(0x59F4F4F0),
                            ),
                            // The walk-back-one-set control — reachable from
                            // EVERY phase (rest included), and only present
                            // when there is actually something to undo, so the
                            // header stays exactly as designed until then.
                            // Top-LEFT, under the segment bar: back is a
                            // navigation control and every other one on this
                            // screen (Close, the system edge-swipe) lives on
                            // that side. It sat on the right purely because
                            // the handoff had nothing there.
                            if (_c.session.previousResolvedSet != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SessionBackChip(
                                  key: const Key('back-chip'),
                                  onTap: _c.back,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        // Paused freezes the rest/elapsed clocks (model state), but a
                        // paused session is still visually "on hold" — dim the phase
                        // content and block its taps, no animation (kept minimal —
                        // prominence here is about info hierarchy, not motion).
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: _c.session.isPaused,
                                child: Opacity(
                                  opacity: _c.session.isPaused ? 0.35 : 1,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 280),
                                    transitionBuilder: (child, animation) =>
                                        reducedMotion(context)
                                        ? FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          )
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
                                      child: _buildPhase(accent, vivid),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Paused, the whole phase is inert — so the dimmed
                            // area itself becomes the way back. The rest and
                            // warm-up phases now carry their own pause control
                            // (the eyebrow pill and the ring), and BOTH live
                            // inside that inert region: without this, tapping
                            // the thing you just used to pause did nothing,
                            // and the only exit was a header toggle that
                            // doesn't look like a button.
                            if (_c.session.isPaused && !_c.session.isComplete)
                              Positioned.fill(
                                child: Semantics(
                                  button: true,
                                  label: l(context).workoutResume,
                                  child: GestureDetector(
                                    key: const Key('paused-resume-overlay'),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _c.togglePause();
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // The persistent music companion — docked BELOW the
                      // phase for the whole session, OUTSIDE the phase switcher
                      // so it never fades or reflows on a phase change. It
                      // collapses to nothing when there's no track to control.
                      // The paused overlay dims the phase above it, not this:
                      // playback is independent of the workout being on hold.
                      if (musicController != null)
                        SessionNowPlaying(
                          key: const Key('session-music-bar'),
                          controller: musicController,
                          density: SpotifyStripDensity.bar,
                          padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
                          accent: vivid,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The screen's background wash for the current phase, with the live
  /// track's accent blended in as a whisper.
  RadialGradient _screenTint(Color? accent) {
    final base = _c.restRemaining != null
        ? TrainColors.restTint
        : TrainColors.setTint;
    if (accent == null) return base;
    return RadialGradient(
      center: base.center,
      radius: base.radius,
      stops: base.stops,
      colors: [for (final c in base.colors) Color.lerp(c, accent, 0.12)!],
    );
  }

  // ---- Header derivations -------------------------------------------------
  //
  // The segment bar counts EXERCISES, not sets: "exercise 4 of 10" is the
  // unit that actually means something mid-workout, and a continuous bar
  // over every set never told you how much of the session was left in a way
  // you could feel.

  int get _exerciseCount => _c.session.exercises.length;

  /// The index of the exercise holding the current pending set, or null once
  /// everything is resolved.
  int? get _currentExerciseIndex {
    final index = _c.session.exercises.indexWhere(
      (e) => e.sets.any((s) => s.pending),
    );
    return index < 0 ? null : index;
  }

  int get _exercisesBehind => _currentExerciseIndex ?? _exerciseCount;

  String get _exerciseCaption {
    if (_exerciseCount == 0) return l(context).liveNoExercises;
    final position = (_currentExerciseIndex ?? _exerciseCount - 1) + 1;
    return 'EXERCISE $position / $_exerciseCount';
  }

  /// The running tally on the right of the caption row. During rest it
  /// switches to echoing the set you just logged — the confirmation that
  /// what you did was recorded, right where you last looked.
  String get _tallyCaption {
    if (_c.restRemaining != null) {
      final previous = _c.session.previousResolvedSet;
      final set = previous?.$2;
      if (set != null && set.done) {
        final reps = set.actualReps;
        final weight = set.actualWeightKg;
        if (reps != null) {
          final load = weight == null ? '' : ' × ${trimWeight(weight)}';
          return l(context).liveSetLoggedDetail('$reps$load');
        }
      }
      return l(context).liveSetLogged;
    }
    final done = _c.session.completedSetCount;
    return l(context).liveSetsLogged(done.toString().padLeft(2, '0'));
  }

  String get _phaseKey {
    if (_c.session.isComplete) return 'completed';
    if (_c.warmupRemaining != null) return 'warmup';
    if (_c.restRemaining != null) return 'resting';
    return 'running:${_c.session.currentSet?.id}';
  }

  Widget _buildPhase(Color? accent, Color? vivid) {
    if (_c.session.isComplete) {
      return CompletedPhase(
        controller: _c,
        dayLabel: widget.day.label,
        onEditSet: _reviewSet,
        onFinish: _onFinish,
      );
    }
    if (_c.warmupRemaining != null) {
      return CountdownPhase(
        key: const ValueKey('warmup'),
        remaining: _c.warmupRemaining ?? Duration.zero,
        totalSeconds: _c.warmupTotalSeconds ?? 1,
        isPaused: _c.session.isPaused,
        hue: TrainColors.ember,
        accent: vivid,
        label: l(context).livePreWorkout,
        pausedLabel: l(context).livePaused,
        runningIcon: AppIcons.streak,
        upNextLabel: l(context).liveFirstUp,
        exercise: _c.session.currentExercise,
        set: _c.session.currentSet,
        skipLabel: l(context).liveSkipWarmUp,
        adjustKeyPrefix: 'warmup',
        onTogglePause: _c.togglePause,
        onAdjust: _c.adjustWarmup,
        onSkip: _c.endWarmup,
      );
    }
    if (_c.restRemaining != null) {
      return CountdownPhase(
        key: const ValueKey('resting'),
        remaining: _c.restRemaining ?? Duration.zero,
        totalSeconds: _c.restTotalSeconds ?? 1,
        isPaused: _c.session.isPaused,
        hue: TrainColors.green,
        accent: vivid,
        label: l(context).liveRest,
        pausedLabel: l(context).livePausedCaps,
        runningGlyph: const TrainPauseGlyph(color: TrainColors.green, size: 11),
        upNextLabel: null,
        exercise: _c.session.currentExercise,
        set: _c.session.currentSet,
        skipLabel: l(context).liveSkipRest,
        adjustKeyPrefix: 'rest',
        onTogglePause: _c.togglePause,
        onAdjust: _c.adjustRest,
        onSkip: _c.endRest,
      );
    }
    return RunningPhase(
      controller: _c,
      accent: accent,
      onDone: _onSetDone,
      onSkip: _onSetSkip,
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
    final result = await showZivoSheet<(int?, double?)>(
      context: context,
      builder: (_) => SetReviewSheet(
        title: '${exercise.name} · Set $position',
        wasSkipped: set.skipped,
        initialReps: set.actualReps,
        initialWeight: set.actualWeightKg,
      ),
    );
    if (result == null || !mounted) return;
    final (reps, weight) = result;
    _c.updateSetActuals(
      exercise.id,
      set.id,
      actualReps: reps,
      actualWeightKg: weight,
      outcome: SetOutcome.completed,
    );
  }

  /// What the user will do when the current rest ends — the (already
  /// advanced) current set/exercise, or Finish if the session is complete.
}

// ---- Formatting -------------------------------------------------------------

// ---- Small building blocks ----------------------------------------------
