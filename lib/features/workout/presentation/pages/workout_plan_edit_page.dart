import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/rep_target.dart';
import '../../domain/set_type.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_plan_source.dart';
import '../../domain/workout_plan_status.dart';
import '../../domain/workout_set.dart';

/// The next cycle slot letter for a plan that already has [count] days: A, B,
/// C… (falls back to a number past Z).
String _slotForIndex(int count) => count < 26 ? String.fromCharCode(0x41 + count) : '${count + 1}';

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// A mutable day while editing — its exercises are fully-formed
/// [PlannedExercise]s (built by the exercise sheet), so drafts round-trip
/// losslessly through save.
class _DayDraft {
  _DayDraft({
    required this.id,
    required this.slot,
    required this.label,
    this.notes,
    List<PlannedExercise>? exercises,
  }) : exercises = exercises ?? <PlannedExercise>[];

  final String id;
  final String slot;
  final String label;
  final String? notes;
  final List<PlannedExercise> exercises;
}

/// Create or edit the workout plan — name, days (slot + label), and exercises
/// within a day (added or edited in place via a sheet that captures a compact
/// set spec and generates the working sets). Saving persists the whole plan,
/// reusing its id when editing so it overwrites idempotently, and preserving
/// the rotation cursor. Dark, matching the session/plan/history screens on
/// the app-wide [AppColors] theme.
class WorkoutPlanEditPage extends StatefulWidget {
  const WorkoutPlanEditPage({super.key, this.initialPlan});

  final WorkoutPlan? initialPlan;

  @override
  State<WorkoutPlanEditPage> createState() => _WorkoutPlanEditPageState();
}

class _WorkoutPlanEditPageState extends State<WorkoutPlanEditPage> {
  late final TextEditingController _name;
  late final String _planId;
  late final DateTime _createdAt;
  late final int _cycleCursor;
  final List<_DayDraft> _days = [];
  bool _canSave = false;

  bool get _editing => widget.initialPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.initialPlan;
    _name = TextEditingController(text: plan?.name ?? '');
    _planId = plan?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _createdAt = plan?.createdAt ?? DateTime.now();
    _cycleCursor = plan?.cycleCursor ?? 0;
    if (plan != null) {
      _days.addAll(
        plan.days.map(
          (d) => _DayDraft(
            id: d.id,
            slot: d.slot,
            label: d.label,
            notes: d.notes,
            exercises: List.of(d.exercises),
          ),
        ),
      );
    }
    _name.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _recompute() {
    final canSave = _name.text.trim().isNotEmpty && _days.isNotEmpty;
    if (canSave != _canSave) setState(() => _canSave = canSave);
  }

  Future<void> _addDay() async {
    final result = await showModalBottomSheet<_DayDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DaySheet(suggestedSlot: _slotForIndex(_days.length)),
    );
    if (result == null) return;
    setState(() => _days.add(result));
    _recompute();
  }

  void _removeDay(int index) {
    setState(() => _days.removeAt(index));
    _recompute();
  }

  Future<void> _addExercise(int dayIndex) async {
    final exercise = await showModalBottomSheet<PlannedExercise>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ExerciseSheet(),
    );
    if (exercise == null) return;
    setState(() => _days[dayIndex].exercises.add(exercise));
  }

  /// Opens the exercise sheet pre-filled with the exercise already at
  /// [exerciseIndex] and, on save, replaces it in place — the whole point
  /// being that editing an exercise no longer means deleting and re-adding
  /// it (which loses its position in the day and its id).
  Future<void> _editExercise(int dayIndex, int exerciseIndex) async {
    final current = _days[dayIndex].exercises[exerciseIndex];
    final exercise = await showModalBottomSheet<PlannedExercise>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExerciseSheet(initial: current),
    );
    if (exercise == null) return;
    setState(() => _days[dayIndex].exercises[exerciseIndex] = exercise);
  }

  void _removeExercise(int dayIndex, int exerciseIndex) {
    setState(() => _days[dayIndex].exercises.removeAt(exerciseIndex));
  }

  /// The wheel's seed when opening the default-rest sheet — the first
  /// exercise's own rest if there is one, so re-opening it after already
  /// bulk-setting a value starts from that value rather than always 1:30.
  int _currentSeedRest() {
    for (final day in _days) {
      for (final exercise in day.exercises) {
        return exercise.defaultRestSeconds;
      }
    }
    return 90;
  }

  /// Sets EVERY exercise's rest, across every day, to one chosen value —
  /// the bulk counterpart to the per-exercise override in [_editExercise].
  /// Per-exercise overrides made *after* this still stick; a later bulk
  /// apply overwrites them again, same as re-running any bulk action.
  Future<void> _pickDefaultRest() async {
    final seconds = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DefaultRestSheet(initialSeconds: _currentSeedRest()),
    );
    if (seconds == null) return;
    setState(() {
      for (final day in _days) {
        for (var i = 0; i < day.exercises.length; i++) {
          final exercise = day.exercises[i];
          day.exercises[i] = exercise.copyWith(
            defaultRestSeconds: seconds,
            sets: [for (final set in exercise.sets) set.copyWith(restSeconds: seconds)],
          );
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final now = DateTime.now();
    final days = <WorkoutDay>[];
    for (var i = 0; i < _days.length; i++) {
      final draft = _days[i];
      days.add(
        WorkoutDay(
          id: draft.id,
          slot: draft.slot,
          label: draft.label,
          notes: draft.notes,
          order: i,
          exercises: [
            for (var j = 0; j < draft.exercises.length; j++) draft.exercises[j].copyWith(order: j),
          ],
        ),
      );
    }
    final plan = WorkoutPlan(
      id: _planId,
      name: _name.text.trim(),
      status: WorkoutPlanStatus.active,
      source: WorkoutPlanSource.manual,
      createdAt: _createdAt,
      updatedAt: now,
      // Keep the rotation where it was; clamp in case days were removed.
      cycleCursor: days.isEmpty ? 0 : _cycleCursor % days.length,
      days: days,
    );
    await AppScope.of(context).workoutPlans.savePlan(plan);
    if (mounted) Navigator.of(context).pop(plan);
  }

  Future<void> _delete() async {
    final plan = widget.initialPlan;
    if (plan == null) return;
    final plans = AppScope.of(context).workoutPlans;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete this plan?', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
        content: Text(
          'This removes "${plan.name}" and all its days and exercises. This can\'t be undone.',
          style: AppText.body.copyWith(color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppText.button.copyWith(color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: AppText.button.copyWith(color: AppColors.flare)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await plans.deletePlan(plan.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureTopBar(
              title: _editing ? 'Edit workout plan' : 'New workout plan',
              onClose: () => Navigator.of(context).maybePop(),
              titleColor: AppColors.ink2,
              iconColor: AppColors.ink2,
              chipColor: AppColors.surfaceRaised,
              trailing: _editing
                  ? CaptureIconButton(
                      key: const Key('workout-plan-delete'),
                      icon: Icons.delete_outline_rounded,
                      onTap: _delete,
                      semanticLabel: 'Delete plan',
                      iconColor: AppColors.flare,
                      chipColor: AppColors.surfaceRaised,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
              child: TextField(
                key: const Key('plan-name-field'),
                controller: _name,
                textInputAction: TextInputAction.done,
                cursorColor: AppColors.pulse,
                style: AppText.cardTitle.copyWith(fontSize: 24, color: AppColors.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Plan name',
                  hintStyle: AppText.cardTitle.copyWith(fontSize: 24, color: AppColors.ink3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
              child: _DefaultRestRow(
                seconds: _currentSeedRest(),
                onTap: _pickDefaultRest,
              ),
            ),
            Expanded(
              child: _days.isEmpty
                  ? _EmptyDays(onAdd: _addDay)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                      itemCount: _days.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == _days.length) {
                          return _AddButton(label: 'Add day', onTap: _addDay);
                        }
                        return _DayCard(
                          day: _days[i],
                          onRemoveDay: () => _removeDay(i),
                          onAddExercise: () => _addExercise(i),
                          onEditExercise: (ei) => _editExercise(i, ei),
                          onRemoveExercise: (ei) => _removeExercise(i, ei),
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 8,
              ),
              child: PillButton(
                label: 'Save plan',
                icon: Icons.check_rounded,
                color: AppColors.pulse,
                enabled: _canSave,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDays extends StatelessWidget {
  const _EmptyDays({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_rounded, size: 30, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text('No days yet.', style: AppText.aside.copyWith(color: AppColors.ink2)),
          const SizedBox(height: 14),
          _AddButton(label: 'Add day', onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap, this.compact = false});

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: compact ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: compact ? 14 : 17, color: AppColors.pulse),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.button.copyWith(
                  fontSize: compact ? 12.5 : 14,
                  color: AppColors.pulse,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The discoverable bulk-rest control — "where's Edit Rest" for the whole
/// plan at once. Shows the value it'll apply so it reads as a real control,
/// not a mystery button.
class _DefaultRestRow extends StatelessWidget {
  const _DefaultRestRow({required this.seconds, required this.onTap});

  final int seconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.pulse),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Default rest · ${restLabel(seconds)}',
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  'Set all',
                  style: AppText.meta.copyWith(color: AppColors.pulse, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bulk-rest sheet — the same dark [_RestPicker] wheel used for a single
/// exercise's rest, but its result applies to every exercise in the plan at
/// once (see [_WorkoutPlanEditPageState._pickDefaultRest]).
class _DefaultRestSheet extends StatefulWidget {
  const _DefaultRestSheet({required this.initialSeconds});

  final int initialSeconds;

  @override
  State<_DefaultRestSheet> createState() => _DefaultRestSheetState();
}

class _DefaultRestSheetState extends State<_DefaultRestSheet> {
  late int _seconds = widget.initialSeconds;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Default rest',
      children: [
        Text(
          'Sets every exercise in this plan to this rest. Editing one exercise '
          'afterward still overrides it individually.',
          style: AppText.body.copyWith(color: AppColors.ink2, fontSize: 13.5),
        ),
        const SizedBox(height: 16),
        _RestPicker(initialSeconds: _seconds, onChanged: (v) => _seconds = v),
        const SizedBox(height: 22),
        PillButton(
          label: 'Set all',
          icon: Icons.check_rounded,
          color: AppColors.pulse,
          enabled: true,
          onTap: () => Navigator.of(context).pop(_seconds),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onEditExercise,
    required this.onRemoveExercise,
  });

  final _DayDraft day;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddExercise;
  final void Function(int exerciseIndex) onEditExercise;
  final void Function(int exerciseIndex) onRemoveExercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day ${day.slot} · ${day.label}',
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              PressableScale(
                child: IconButton(
                  onPressed: onRemoveDay,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink3),
                  splashRadius: 20,
                  tooltip: 'Remove day',
                ),
              ),
            ],
          ),
          if (day.notes != null && day.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(day.notes!, style: AppText.meta.copyWith(color: AppColors.ink3)),
            ),
          for (var ei = 0; ei < day.exercises.length; ei++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _ExerciseRow(
                exercise: day.exercises[ei],
                onEdit: () => onEditExercise(ei),
                onRemove: () => onRemoveExercise(ei),
              ),
            ),
          const SizedBox(height: 10),
          _AddButton(label: 'Add exercise', onTap: onAddExercise, compact: true),
        ],
      ),
    );
  }
}

/// One exercise within a day card — tapping it opens the exercise sheet
/// pre-filled for editing in place; the trailing X stays a separate, direct
/// remove action.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onEdit, required this.onRemove});

  final PlannedExercise exercise;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _setSpecLabel(exercise),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(color: AppColors.pulse),
                      ),
                    ],
                  ),
                ),
                PressableScale(
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.ink3),
                    splashRadius: 18,
                    tooltip: 'Remove exercise',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "3 × 6–8 · 60kg · rest 1:30" — the compact set spec read back off the
  /// generated sets (all identical for a manually-added exercise).
  String _setSpecLabel(PlannedExercise e) {
    if (e.sets.isEmpty) return 'No sets';
    final first = e.sets.first;
    final parts = <String>[
      '${e.sets.length} × ${repTargetLabel(first.repTarget)}',
      if (first.targetWeightKg != null) '${_trimWeight(first.targetWeightKg!)}kg',
      'rest ${restLabel(first.restSeconds)}',
    ];
    return parts.join(' · ');
  }
}

/// A sheet to add one day: a slot letter, a label, and optional notes.
class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.suggestedSlot});

  final String suggestedSlot;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late final TextEditingController _slot = TextEditingController(text: widget.suggestedSlot);
  final TextEditingController _label = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _label.addListener(() {
      final canAdd = _label.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _slot.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    final slot = _slot.text.trim().isEmpty ? widget.suggestedSlot : _slot.text.trim();
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      _DayDraft(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        slot: slot,
        label: _label.text.trim(),
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Add day',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: _LabeledField(label: 'Slot', controller: _slot, hint: 'A'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledField(
                fieldKey: const Key('day-label-field'),
                label: 'Label',
                controller: _label,
                hint: 'Push / Pull / Legs',
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _LabeledField(label: 'Notes (optional)', controller: _notes, hint: '—'),
        const SizedBox(height: 22),
        PillButton(
          label: 'Add day',
          icon: Icons.add_rounded,
          color: AppColors.pulse,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}

enum _RepMode { fixed, range, toFailure }

/// A sheet to add or edit one exercise via a compact set spec: name, muscle
/// group, a set count, a rep target (fixed / range / to-failure), a rest
/// wheel, and an optional weight — which it expands into that many identical
/// working sets. Passing [initial] pre-fills every field from that exercise
/// and, on submit, keeps its id so the caller can replace it in place rather
/// than append a new one.
class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet({this.initial});

  final PlannedExercise? initial;

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _sets = TextEditingController(text: '3');
  final TextEditingController _reps = TextEditingController(text: '8');
  final TextEditingController _repsMax = TextEditingController(text: '12');
  final TextEditingController _weight = TextEditingController();
  _RepMode _mode = _RepMode.range;
  int _restSeconds = 90;
  bool _canAdd = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      _muscle.text = initial.muscleGroup ?? '';
      _sets.text = '${initial.sets.length}';
      final first = initial.sets.isNotEmpty ? initial.sets.first : null;
      if (first != null) {
        _mode = switch (first.repTarget.kind) {
          RepTargetKind.fixed => _RepMode.fixed,
          RepTargetKind.range => _RepMode.range,
          RepTargetKind.toFailure => _RepMode.toFailure,
        };
        if (first.repTarget.min != null) _reps.text = '${first.repTarget.min}';
        if (first.repTarget.max != null) _repsMax.text = '${first.repTarget.max}';
        if (first.targetWeightKg != null) _weight.text = _trimWeight(first.targetWeightKg!);
        _restSeconds = first.restSeconds;
      } else {
        _restSeconds = initial.defaultRestSeconds;
      }
    }
    _canAdd = _name.text.trim().isNotEmpty;
    _name.addListener(() {
      final canAdd = _name.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _muscle.dispose();
    _sets.dispose();
    _reps.dispose();
    _repsMax.dispose();
    _weight.dispose();
    super.dispose();
  }

  RepTarget _buildTarget() {
    switch (_mode) {
      case _RepMode.fixed:
        final reps = int.tryParse(_reps.text.trim()) ?? 1;
        return RepTarget.fixed(reps < 1 ? 1 : reps);
      case _RepMode.range:
        var lo = int.tryParse(_reps.text.trim()) ?? 1;
        var hi = int.tryParse(_repsMax.text.trim()) ?? lo;
        if (lo < 1) lo = 1;
        if (hi < lo) hi = lo;
        return RepTarget.range(lo, hi);
      case _RepMode.toFailure:
        return const RepTarget.toFailure();
    }
  }

  void _submit() {
    if (!_canAdd) return;
    final count = (int.tryParse(_sets.text.trim()) ?? 1).clamp(1, 20);
    final weightRaw = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    final weight = (weightRaw == null || weightRaw <= 0) ? null : weightRaw;
    final target = _buildTarget();
    final muscle = _muscle.text.trim();
    final initial = widget.initial;
    Navigator.of(context).pop(
      PlannedExercise(
        id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        order: initial?.order ?? 0,
        muscleGroup: muscle.isEmpty ? null : muscle,
        defaultRestSeconds: _restSeconds,
        sets: [
          for (var i = 0; i < count; i++)
            PlannedSet(
              order: i,
              repTarget: target,
              restSeconds: _restSeconds,
              targetWeightKg: weight,
              type: SetType.working,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: _editing ? 'Edit exercise' : 'Add exercise',
      children: [
        _LabeledField(
          fieldKey: const Key('exercise-name-field'),
          label: 'Name',
          controller: _name,
          hint: 'Bench Press',
          autofocus: !_editing,
        ),
        const SizedBox(height: 14),
        _LabeledField(label: 'Muscle group (optional)', controller: _muscle, hint: 'Chest'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 76, child: _NumberField(label: 'Sets', controller: _sets)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REP TARGET',
                    style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      SelectChip(
                        label: 'Fixed',
                        selected: _mode == _RepMode.fixed,
                        onTap: () => setState(() => _mode = _RepMode.fixed),
                      ),
                      SelectChip(
                        label: 'Range',
                        selected: _mode == _RepMode.range,
                        onTap: () => setState(() => _mode = _RepMode.range),
                      ),
                      SelectChip(
                        label: 'To failure',
                        selected: _mode == _RepMode.toFailure,
                        onTap: () => setState(() => _mode = _RepMode.toFailure),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_mode != _RepMode.toFailure) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: _mode == _RepMode.range ? 'Min reps' : 'Reps',
                  controller: _reps,
                ),
              ),
              if (_mode == _RepMode.range) ...[
                const SizedBox(width: 12),
                Expanded(child: _NumberField(label: 'Max reps', controller: _repsMax)),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RestPicker(
                initialSeconds: _restSeconds,
                onChanged: (v) => _restSeconds = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _NumberField(label: 'Weight (kg)', controller: _weight, hint: '—')),
          ],
        ),
        const SizedBox(height: 22),
        PillButton(
          label: _editing ? 'Save changes' : 'Add exercise',
          icon: _editing ? Icons.check_rounded : Icons.add_rounded,
          color: AppColors.pulse,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// A dark, physical rest-duration wheel — 5s increments up to 5:00, with a
/// native scroll-tick haptic on every value that settles under the band.
/// Replaces a free-text seconds field: rest is a duration people dial in by
/// feel, not a number they type.
class _RestPicker extends StatefulWidget {
  const _RestPicker({required this.initialSeconds, required this.onChanged});

  final int initialSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<_RestPicker> createState() => _RestPickerState();
}

class _RestPickerState extends State<_RestPicker> {
  static const _stepSeconds = 5;
  static const _maxSeconds = 300;

  late final FixedExtentScrollController _controller = FixedExtentScrollController(
    initialItem: widget.initialSeconds.clamp(0, _maxSeconds) ~/ _stepSeconds,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('REST', style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.6)),
        const SizedBox(height: 6),
        Container(
          height: 132,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: CupertinoPicker(
            key: const Key('rest-picker'),
            scrollController: _controller,
            itemExtent: 34,
            diameterRatio: 1.4,
            backgroundColor: Colors.transparent,
            selectionOverlay: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSelectedItemChanged: (index) {
              if (!reducedMotion(context)) HapticFeedback.selectionClick();
              widget.onChanged(index * _stepSeconds);
            },
            children: [
              for (var s = 0; s <= _maxSeconds; s += _stepSeconds)
                Center(
                  child: Text(
                    restLabel(s),
                    style: AppText.rowTitle.copyWith(color: AppColors.ink),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The shared bottom-sheet chrome (grabber + title + content), matching the
/// session/plan screens' dark palette.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 12,
          left: 22,
          right: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(title, style: AppText.cardTitle.copyWith(color: AppColors.ink)),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled single-line text field for the sheets.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.6),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.next,
          onSubmitted: onSubmitted,
          cursorColor: AppColors.pulse,
          style: AppText.rowTitle.copyWith(color: AppColors.ink),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.hairline2)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.hairline2),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.pulse, width: 1.6),
            ),
            hintText: hint,
            hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.controller, this.hint});

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          style: AppText.rowTitle.copyWith(color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            filled: true,
            fillColor: AppColors.surfaceRaised,
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
    );
  }
}
