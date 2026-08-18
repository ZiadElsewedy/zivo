import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/exercise_history.dart';
import '../../domain/live_session.dart';
import '../../domain/live_session_to_workout_log.dart';
import '../../domain/logged_set.dart';
import '../../domain/rep_target.dart';
import '../../domain/session_exercise.dart';
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
  const LiveSessionPage({required this.day, required this.plan, this.resume, super.key});

  /// The day to run (a snapshot embedded in the session).
  final WorkoutDay day;

  /// The active plan — needed to advance its cursor when the session finishes.
  final WorkoutPlan plan;

  /// A previously-saved active session to resume into, in place of starting a
  /// fresh one from [day]. Passed by the plan page once it has an active
  /// session for this plan/day (`WorkoutSessionRepository.activeSession`).
  final LiveSession? resume;

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> {
  late LiveSession _session;

  final TextEditingController _reps = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  Timer? _restTimer;
  int? _restRemaining;
  int? _restTotalSeconds;

  bool _reposInitialized = false;
  late WorkoutSessionRepository _sessionsRepo;
  StreamSubscription<List<LiveSession>>? _pastSessionsSub;
  List<LiveSession> _pastSessions = const [];

  /// Guards [_onFinish]/[_onLeave]/[_onDiscard] against re-entrancy — all are
  /// async and otherwise callable again (double-tap, or Finish racing the
  /// close button) before the first call's writes/pop land.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _session =
        widget.resume ??
        LiveSession.start(
          widget.day,
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          planId: widget.plan.id,
          now: DateTime.now(),
        );
    if (_session.currentSet == null) {
      // Nothing to do (an empty day) — settle straight into the completed view.
      _session = _session.complete(now: DateTime.now());
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
    });
    unawaited(_sessionsRepo.saveSession(_session));
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _pastSessionsSub?.cancel();
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ---- Input prefill -------------------------------------------------------

  void _prefillInputs() {
    final set = _session.currentSet;
    _reps.text = (set != null && set.target.kind == RepTargetKind.fixed)
        ? '${set.target.min}'
        : '';
    _weight.text = (set?.targetWeightKg != null) ? _trimWeight(set!.targetWeightKg!) : '';
  }

  // ---- Previous performance --------------------------------------------------

  ExerciseHistory? _historyFor(SessionExercise exercise) =>
      lastPerformanceFor(exercise.exerciseId, _pastSessions);

  LoggedSet? _previousSetFor(SessionExercise exercise, LoggedSet set) {
    final history = _historyFor(exercise);
    if (history == null) return null;
    final index = exercise.sets.indexOf(set);
    if (index < 0 || index >= history.sets.length) return null;
    return history.sets[index];
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
        _session = _session.complete(now: DateTime.now());
      }
    });
    unawaited(_sessionsRepo.saveSession(_session));
    _prefillInputs();
    if (_session.isComplete) {
      _restTimer?.cancel();
      _restTotalSeconds = null;
      setState(() => _restRemaining = null);
      return;
    }
    _startRest(exercise.restSeconds);
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    if (seconds <= 0) {
      setState(() {
        _restRemaining = null;
        _restTotalSeconds = null;
      });
      return;
    }
    _restTotalSeconds = seconds;
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _restRemaining ?? 0;
      if (remaining <= 1) {
        _endRest();
      } else {
        setState(() => _restRemaining = remaining - 1);
      }
    });
  }

  void _endRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restTotalSeconds = null;
    if (mounted) setState(() => _restRemaining = null);
  }

  void _adjustRest(int delta) {
    final next = (_restRemaining ?? 0) + delta;
    if (next <= 0) {
      _endRest();
    } else {
      setState(() => _restRemaining = next);
    }
  }

  Future<void> _onFinish() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Read repositories before the first await (the app's capture convention).
    final workouts = AppScope.of(context).workouts;
    final plans = AppScope.of(context).workoutPlans;
    final sessions = _sessionsRepo;
    await workouts.add(_session.toWorkoutLog());
    await plans.savePlan(widget.plan.advanceCursor());
    await sessions.saveSession(_session);
    if (mounted) Navigator.of(context).pop();
  }

  /// LEAVE: the close (X) button and the system/edge-swipe back gesture. The
  /// session already autosaves as it's played, so leaving just pops — no
  /// confirmation, nothing deleted, the plan's cursor untouched. The one
  /// exception: a session with zero logged sets is indistinguishable from
  /// never having started one, so it's discarded silently rather than left
  /// behind as a "Resume" with nothing in it.
  Future<void> _onLeave() async {
    if (_busy) return;
    setState(() => _busy = true);
    _restTimer?.cancel();
    if (_session.completedSetCount == 0) {
      await _sessionsRepo.deleteSession(_session.id);
    }
    if (mounted) Navigator.of(context).pop();
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
    await sessions.deleteSession(_session.id);
    if (mounted) Navigator.of(context).pop();
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
              Expanded(
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
    final target = set.target;
    final targetText = target.kind == RepTargetKind.toFailure
        ? 'To failure'
        : '${repTargetLabel(target)} reps';
    final previousSet = _previousSetFor(exercise, set);
    final previousLabel = _formatPrevious(previousSet);
    final setIndex = exercise.sets.indexOf(set);

    return ListView(
      key: const ValueKey('running-list'),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        StaggeredReveal(
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SET ${setIndex + 1} OF ${exercise.setCount}',
                style: AppText.meta.copyWith(
                  color: AppColors.emberText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(exercise.name, style: AppText.cardTitle.copyWith(fontSize: 28)),
              const SizedBox(height: 6),
              Text('Target: $targetText', style: AppText.rowTitle.copyWith(color: AppColors.ink2)),
              if (exercise.muscleGroup != null) ...[
                const SizedBox(height: 2),
                Text(exercise.muscleGroup!, style: AppText.meta.copyWith(color: AppColors.ink3)),
              ],
              if (previousLabel != null) ...[
                const SizedBox(height: 10),
                Text(previousLabel, style: AppText.meta.copyWith(color: AppColors.ink3)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        StaggeredReveal(
          index: 1,
          child: _SetChipRow(exercise: exercise, currentSetId: set.id),
        ),
        const SizedBox(height: 22),
        StaggeredReveal(
          index: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ActualField(label: 'Reps', controller: _reps, onChanged: () => setState(() {})),
                  const SizedBox(width: 14),
                  _ActualField(
                    label: 'Weight (kg)',
                    controller: _weight,
                    hint: '—',
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
              _ProgressionDelta(previousSet: previousSet, weightController: _weight),
            ],
          ),
        ),
        const SizedBox(height: 26),
        StaggeredReveal(
          index: 3,
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
    final setIndex = exercise.sets.indexOf(set);
    return 'Set ${setIndex + 1} · ${exercise.name}';
  }
}

// ---- Formatting -------------------------------------------------------------

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "Day A · Push".
String _dayTitle(WorkoutDay day) => 'Day ${day.slot} · ${day.label}';

/// "Previous 60kg × 8" — omits either half when unset; null when there's
/// nothing to show.
String? _formatPrevious(LoggedSet? previous) {
  if (previous == null) return null;
  final parts = <String>[
    if (previous.actualWeightKg != null) '${_trimWeight(previous.actualWeightKg!)}kg',
    if (previous.actualReps != null) '× ${previous.actualReps}',
  ];
  if (parts.isEmpty) return null;
  return 'Previous ${parts.join(' ')}';
}

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
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            cursorColor: AppColors.ember,
            style: AppText.rowTitle,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < exercise.sets.length; i++)
          _SetChip(
            number: i + 1,
            state: exercise.sets[i].done
                ? _ChipState.done
                : exercise.sets[i].id == currentSetId
                ? _ChipState.current
                : _ChipState.upcoming,
          ),
      ],
    );
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
