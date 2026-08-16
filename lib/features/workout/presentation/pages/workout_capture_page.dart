import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/exercise.dart';
import '../../domain/workout.dart';
import '../../domain/workout_format.dart';

/// Workout create-or-edit — name the session, add a few exercises, save. A
/// Pulse screen; lightweight logging over rigid tracking. Pass [initial] to
/// edit an existing logged workout in place instead of creating a new one;
/// editing preserves the workout's original `performedAt`/`durationMinutes`.
class WorkoutCapturePage extends StatefulWidget {
  const WorkoutCapturePage({super.key, this.initial});

  final Workout? initial;

  @override
  State<WorkoutCapturePage> createState() => _WorkoutCapturePageState();
}

class _WorkoutCapturePageState extends State<WorkoutCapturePage> {
  final TextEditingController _title = TextEditingController();
  final List<Exercise> _exercises = [];
  bool _canSave = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _title.text = initial.title;
      _exercises.addAll(initial.exercises);
    }
    _canSave = _title.text.trim().isNotEmpty && _exercises.isNotEmpty;
    _title.addListener(_recompute);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _recompute() {
    final canSave = _title.text.trim().isNotEmpty && _exercises.isNotEmpty;
    if (canSave != _canSave) setState(() => _canSave = canSave);
  }

  Future<void> _addExercise() async {
    final result = await showModalBottomSheet<Exercise>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ExerciseSheet(),
    );
    if (result == null) return;
    setState(() => _exercises.add(result));
    _recompute();
  }

  void _removeExercise(int index) {
    setState(() => _exercises.removeAt(index));
    _recompute();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final initial = widget.initial;
    final workout = Workout(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      performedAt: initial?.performedAt ?? DateTime.now(),
      durationMinutes: initial?.durationMinutes,
      exercises: List.unmodifiable(_exercises),
    );
    final workouts = AppScope.of(context).workouts;
    if (initial == null) {
      await workouts.add(workout);
    } else {
      await workouts.update(workout);
    }
    if (mounted) Navigator.of(context).pop(workout);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final workouts = AppScope.of(context).workouts;
    await workouts.remove(initial.id);
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
              title: _editing ? 'Edit workout' : 'New workout',
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? InkWell(
                      key: const Key('workout-delete'),
                      onTap: _delete,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFEBE3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.flareText,
                        ),
                      ),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 6),
              child: TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                cursorColor: AppColors.pulse,
                style: AppText.cardTitle.copyWith(fontSize: 27),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Name this session',
                  hintStyle:
                      AppText.cardTitle.copyWith(fontSize: 27, color: AppColors.ink3),
                ),
              ),
            ),
            Expanded(
              child: _exercises.isEmpty
                  ? _EmptyExercises(onAdd: _addExercise)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                      itemCount: _exercises.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == _exercises.length) {
                          return _AddExerciseButton(onTap: _addExercise);
                        }
                        return _ExerciseRow(
                          exercise: _exercises[i],
                          onRemove: () => _removeExercise(i),
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
                label: 'Save workout',
                icon: Icons.check_rounded,
                color: AppColors.pulseText,
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

class _EmptyExercises extends StatelessWidget {
  const _EmptyExercises({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_rounded, size: 30, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text('No exercises yet.', style: AppText.aside),
          const SizedBox(height: 14),
          _AddExerciseButton(onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddExerciseButton extends StatelessWidget {
  const _AddExerciseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 17, color: AppColors.pulseText),
            const SizedBox(width: 7),
            Text(
              'Add exercise',
              style: AppText.button.copyWith(fontSize: 14, color: AppColors.pulseText),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onRemove});

  final Exercise exercise;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
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
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  setRepLabel(exercise),
                  style: AppText.meta.copyWith(color: AppColors.pulseText),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink3),
            splashRadius: 20,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

/// A compact sheet to add one exercise: a name and its sets · reps · load.
class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet();

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _sets = TextEditingController(text: '3');
  final TextEditingController _reps = TextEditingController(text: '10');
  final TextEditingController _weight = TextEditingController();
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      final canAdd = _name.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    final sets = int.tryParse(_sets.text.trim()) ?? 1;
    final reps = int.tryParse(_reps.text.trim()) ?? 1;
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(
      Exercise(
        name: _name.text.trim(),
        sets: sets < 1 ? 1 : sets,
        reps: reps < 1 ? 1 : reps,
        weightKg: (weight == null || weight <= 0) ? null : weight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
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
            child: Text('Add exercise', style: AppText.cardTitle),
          ),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            cursorColor: AppColors.pulse,
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.pulse, width: 1.6),
              ),
              hintText: 'Exercise name',
              hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _NumberField(label: 'Sets', controller: _sets),
              const SizedBox(width: 12),
              _NumberField(label: 'Reps', controller: _reps),
              const SizedBox(width: 12),
              _NumberField(label: 'Weight (kg)', controller: _weight, hint: '—'),
            ],
          ),
          const SizedBox(height: 22),
          PillButton(
            label: 'Add exercise',
            icon: Icons.add_rounded,
            color: AppColors.pulseText,
            enabled: _canAdd,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.hint,
  });

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
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            cursorColor: AppColors.pulse,
            style: AppText.rowTitle,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              filled: true,
              fillColor: AppColors.ground,
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
