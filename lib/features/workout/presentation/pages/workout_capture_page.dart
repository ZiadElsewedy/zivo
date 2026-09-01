import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/parse.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../core/widgets/zivo_field.dart';
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
    final result = await showZivoSheet<Exercise>(
      context: context,
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
      backgroundColor: TrainColors.base,
      body: DecoratedBox(
        // The same wash the Workout hub carries — a capture flow belongs to
        // the surface that launched it, not to a flat void.
        decoration: const BoxDecoration(gradient: TrainColors.hubTint),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptureTopBar(
                title: _editing ? 'Edit workout' : 'New workout',
                onClose: () => Navigator.of(context).maybePop(),
                trailing: _editing
                    ? CaptureIconButton(
                        key: const Key('workout-delete'),
                        icon: Icons.delete_outline_rounded,
                        onTap: _delete,
                        semanticLabel: 'Delete workout',
                        iconColor: TrainColors.ember,
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 6),
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  cursorColor: TrainColors.green,
                  style: TrainType.ui(
                    size: 27,
                    weight: FontWeight.w800,
                    tracking: -0.025,
                    height: 1.15,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Name this session',
                    hintStyle: TrainType.ui(
                      size: 27,
                      weight: FontWeight.w800,
                      tracking: -0.025,
                      height: 1.15,
                      color: TrainColors.ink4,
                    ),
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
                  color: TrainColors.ember,
                  enabled: _canSave,
                  onTap: _save,
                ),
              ),
            ],
          ),
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
          const Icon(
            Icons.fitness_center_rounded,
            size: 30,
            color: TrainColors.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            'No exercises yet.',
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w400,
              color: TrainColors.ink2,
              height: 1.5,
            ),
          ),
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
          border: Border.all(color: TrainColors.hairline, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 17, color: TrainColors.green),
            const SizedBox(width: 7),
            Text(
              'Add exercise',
              style: TrainType.ui(
                size: 14,
                weight: FontWeight.w700,
                height: 1,
                color: TrainColors.green,
              ),
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
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrainColors.hairline),
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
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  setRepLabel(exercise),
                  style: TrainType.mono(
                    size: 10.5,
                    tracking: 0.06,
                    color: TrainColors.green,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: TrainColors.ink4,
            ),
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
    final sets = parseWhole(_sets.text) ?? 1;
    final reps = parseWhole(_reps.text) ?? 1;
    final weight = parseDecimal(_weight.text);
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
        color: Color(0x08FFFFFF),
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
                color: TrainColors.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'Add exercise',
              style: TrainType.ui(
                size: 20,
                weight: FontWeight.w800,
                tracking: -0.025,
                color: TrainColors.ink,
                height: 1.15,
              ),
            ),
          ),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            cursorColor: TrainColors.green,
            style: TrainType.ui(size: 15, weight: FontWeight.w600, height: 1.1),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.hairline),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: TrainColors.green, width: 1.6),
              ),
              hintText: 'Exercise name',
              hintStyle: TrainType.ui(
                size: 15,
                weight: FontWeight.w700,
                height: 1.1,
                color: TrainColors.ink4,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _NumberField(label: 'Sets', controller: _sets),
              const SizedBox(width: 12),
              _NumberField(label: 'Reps', controller: _reps),
              const SizedBox(width: 12),
              _NumberField(
                label: 'Weight (kg)',
                controller: _weight,
                hint: '—',
              ),
            ],
          ),
          const SizedBox(height: 22),
          PillButton(
            label: 'Add exercise',
            icon: Icons.add_rounded,
            color: TrainColors.ember,
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
            style: TrainType.mono(
              size: 10.5,
              tracking: 0.06,
              color: TrainColors.ink4,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            cursorColor: TrainColors.green,
            style: TrainType.ui(
              size: 15,
              weight: FontWeight.w700,
              color: TrainColors.inkPlain,
              height: 1.1,
            ),
            decoration: zivoFieldDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TrainType.ui(
                size: 15,
                weight: FontWeight.w700,
                height: 1.1,
                color: TrainColors.ink4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
