import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/rep_target.dart';
import '../../domain/session_phase.dart';
import '../../domain/session_to_workout_log.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_session.dart';

/// The guided workout player — walks the user set-by-set through the day's
/// exercises, timing rests in-app and capturing the actual reps/weight per set.
///
/// All state lives in the pure [WorkoutSession] engine (P3a); this widget only
/// drives it through its transitions and renders the current snapshot. On full
/// completion (the Finish button) it writes the session to history AND advances
/// the plan's rotating cursor. Quitting mid-workout DISCARDS: nothing is
/// written and the cursor does not move.
class WorkoutSessionPage extends StatefulWidget {
  const WorkoutSessionPage({required this.day, required this.plan, super.key});

  /// The day to run (a snapshot embedded in the session).
  final WorkoutDay day;

  /// The active plan — needed to advance its cursor when the session completes.
  final WorkoutPlan plan;

  @override
  State<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<WorkoutSessionPage> {
  late WorkoutSession _session;

  final TextEditingController _reps = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  Timer? _restTimer;
  int _remaining = 0;

  /// True right after a rest ends onto a new set, so the running view can show
  /// a "Ready for set N" cue. Cleared once that set is completed.
  bool _readyCue = false;

  @override
  void initState() {
    super.initState();
    _session = WorkoutSession.start(
      widget.day,
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      planId: widget.plan.id,
      now: DateTime.now(),
    );
    _prefillInputs();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ---- Input prefill -------------------------------------------------------

  void _prefillInputs() {
    final set = _session.currentSet;
    // Reps: pre-fill only a fixed target; ranges and to-failure start empty so
    // the user records what they actually hit.
    _reps.text = (set != null && set.repTarget.kind == RepTargetKind.fixed)
        ? '${set.repTarget.min}'
        : '';
    _weight.text = (set?.targetWeightKg != null) ? _trimWeight(set!.targetWeightKg!) : '';
  }

  // ---- Transitions (all through the P3a engine) ----------------------------

  void _onDone() {
    final reps = int.tryParse(_reps.text.trim());
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    setState(() {
      _readyCue = false;
      _session = _session.completeCurrentSet(
        actualReps: reps,
        actualWeightKg: weight,
        now: DateTime.now(),
      );
    });
    if (_session.isResting) {
      _startRest(_session.currentRestSeconds);
    }
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    setState(() => _remaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _endRest();
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  void _endRest() {
    _restTimer?.cancel();
    _restTimer = null;
    setState(() {
      _session = _session.endRest();
      _readyCue = _session.phase == SessionPhase.running;
    });
    if (_session.phase == SessionPhase.running) _prefillInputs();
  }

  void _adjustRest(int delta) {
    final next = _remaining + delta;
    if (next <= 0) {
      _endRest();
      return;
    }
    setState(() => _remaining = next);
  }

  Future<void> _onFinish() async {
    // Read repositories before the first await (the app's capture convention).
    final workouts = AppScope.of(context).workouts;
    final plans = AppScope.of(context).workoutPlans;
    await workouts.add(_session.toWorkoutLog());
    await plans.savePlan(widget.plan.advanceCursor());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onClose() async {
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
    if (confirmed != true) return;
    // DISCARD: cancel the timer, write nothing, do not advance the cursor.
    _restTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(title: _dayTitle(widget.day), onClose: _onClose),
            _ProgressBar(done: _session.completedSetCount, total: _session.totalSets),
            Expanded(child: _buildPhase()),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_session.phase) {
      case SessionPhase.resting:
        return _buildResting();
      case SessionPhase.completed:
        return _buildCompleted();
      case SessionPhase.running:
      case SessionPhase.abandoned:
        return _buildRunning();
    }
  }

  Widget _buildRunning() {
    final exercise = _session.currentExercise;
    final set = _session.currentSet;
    if (exercise == null || set == null) {
      return const Center(child: Text('Nothing to do.'));
    }
    final target = set.repTarget;
    final targetText = target.kind == RepTargetKind.toFailure
        ? 'To failure'
        : '${repTargetLabel(target)} reps';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        if (_readyCue)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Eyebrow('Ready for set ${_session.currentSetNumber}'),
          ),
        Text(
          'Set ${_session.currentSetNumber} of ${_session.exerciseSetCount}',
          style: AppText.meta.copyWith(color: AppColors.pulseText, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(exercise.name, style: AppText.cardTitle.copyWith(fontSize: 28)),
        const SizedBox(height: 6),
        Text('Target: $targetText', style: AppText.rowTitle.copyWith(color: AppColors.ink2)),
        if (exercise.muscleGroup != null) ...[
          const SizedBox(height: 2),
          Text(exercise.muscleGroup!, style: AppText.meta.copyWith(color: AppColors.ink3)),
        ],
        if (exercise.notes != null) ...[
          const SizedBox(height: 8),
          Text(exercise.notes!, style: AppText.body.copyWith(fontSize: 14, color: AppColors.ink2)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            _ActualField(label: 'Reps', controller: _reps),
            const SizedBox(width: 14),
            _ActualField(label: 'Weight (kg)', controller: _weight, hint: '—'),
          ],
        ),
        const SizedBox(height: 26),
        PillButton(
          label: 'Done',
          icon: Icons.check_rounded,
          color: AppColors.pulseText,
          enabled: true,
          onTap: _onDone,
        ),
      ],
    );
  }

  Widget _buildResting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(child: _Eyebrow('Rest')),
          const SizedBox(height: 14),
          Center(
            child: Text(
              restLabel(_remaining),
              style: AppText.greeting.copyWith(fontSize: 64, color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Next: ${_nextUpLabel()}',
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
            color: AppColors.pulseText,
            enabled: true,
            onTap: _endRest,
          ),
        ],
      ),
    );
  }

  Widget _buildCompleted() {
    final elapsed = (_session.completedAt ?? _session.startedAt).difference(_session.startedAt);
    final loggedExercises = widget.day.exercises
        .where((e) => _session.logs.any((l) => l.exerciseId == e.id && l.done))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Center(child: _Eyebrow('Workout complete')),
        const SizedBox(height: 14),
        Center(
          child: Icon(Icons.check_circle_rounded, size: 56, color: AppColors.pulse),
        ),
        const SizedBox(height: 16),
        Text(widget.day.label, style: AppText.cardTitle.copyWith(fontSize: 24)),
        const SizedBox(height: 6),
        Text(
          '${_session.completedSetCount} of ${_session.totalSets} sets · ${elapsed.inMinutes} min',
          style: AppText.meta.copyWith(color: AppColors.pulseText),
        ),
        const SizedBox(height: 18),
        for (final exercise in loggedExercises)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${exercise.name} · ${_doneSetCount(exercise.id)} sets',
              style: AppText.body.copyWith(fontSize: 15, color: AppColors.ink2),
            ),
          ),
        const SizedBox(height: 26),
        PillButton(
          label: 'Finish',
          icon: Icons.check_rounded,
          color: AppColors.pulseText,
          enabled: true,
          onTap: _onFinish,
        ),
      ],
    );
  }

  int _doneSetCount(String exerciseId) =>
      _session.logs.where((l) => l.exerciseId == exerciseId && l.done).length;

  /// What the user will do when the current rest ends — the next set of this
  /// exercise, or the next exercise, or the finish.
  String _nextUpLabel() {
    final exercise = _session.currentExercise;
    if (exercise == null) return 'Finish';
    if (_session.currentSetIndex + 1 < exercise.sets.length) {
      return 'Set ${_session.currentSetIndex + 2} · ${exercise.name}';
    }
    return _session.nextExercise?.name ?? 'Finish';
  }
}

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "Day A · Push".
String _dayTitle(WorkoutDay day) => 'Day ${day.slot} · ${day.label}';

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.meta.copyWith(
        color: AppColors.pulseText,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 5,
          backgroundColor: AppColors.hairline,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.pulse),
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
        child: Text(
          label,
          style: AppText.button.copyWith(fontSize: 15, color: AppColors.ink2),
        ),
      ),
    );
  }
}

class _ActualField extends StatelessWidget {
  const _ActualField({required this.label, required this.controller, this.hint});

  final String label;
  final TextEditingController controller;
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
            cursorColor: AppColors.pulse,
            style: AppText.rowTitle,
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
                borderSide: const BorderSide(color: AppColors.pulse, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
