import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/parse.dart';
import '../../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../domain/planned_exercise.dart';
import '../../../domain/rep_target.dart';
import '../../../domain/set_type.dart';
import '../../../domain/workout_plan_format.dart';
import '../../../domain/workout_set.dart';
import 'plan_edit_chrome.dart';
import '../../workout_format.dart';

enum RepMode { fixed, range, toFailure }

/// A sheet to add or edit one exercise via a compact set spec: name, muscle
/// group, a set count, a rep target (fixed / range / to-failure), a rest
/// wheel, and an optional weight — which it expands into that many identical
/// working sets. Passing [initial] pre-fills every field from that exercise
/// and, on submit, keeps its id so the caller can replace it in place rather
/// than append a new one.
class ExerciseSheet extends StatefulWidget {
  const ExerciseSheet({this.initial, super.key});

  final PlannedExercise? initial;

  @override
  State<ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<ExerciseSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _sets = TextEditingController(text: '3');
  final TextEditingController _reps = TextEditingController(text: '8');
  final TextEditingController _repsMax = TextEditingController(text: '12');
  final TextEditingController _weight = TextEditingController();
  RepMode _mode = RepMode.range;
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
          RepTargetKind.fixed => RepMode.fixed,
          RepTargetKind.range => RepMode.range,
          RepTargetKind.toFailure => RepMode.toFailure,
        };
        if (first.repTarget.min != null) _reps.text = '${first.repTarget.min}';
        if (first.repTarget.max != null) {
          _repsMax.text = '${first.repTarget.max}';
        }
        if (first.targetWeightKg != null) {
          _weight.text = trimWeight(first.targetWeightKg!);
        }
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
      case RepMode.fixed:
        final reps = parseWhole(_reps.text) ?? 1;
        return RepTarget.fixed(reps < 1 ? 1 : reps);
      case RepMode.range:
        var lo = parseWhole(_reps.text) ?? 1;
        var hi = parseWhole(_repsMax.text) ?? lo;
        if (lo < 1) lo = 1;
        if (hi < lo) hi = lo;
        return RepTarget.range(lo, hi);
      case RepMode.toFailure:
        return const RepTarget.toFailure();
    }
  }

  void _submit() {
    if (!_canAdd) return;
    final count = (parseWhole(_sets.text) ?? 1).clamp(1, 20);
    final weightRaw = parseDecimal(_weight.text);
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
    return SheetShell(
      title: _editing ? 'Edit exercise' : 'Add exercise',
      children: [
        LabeledField(
          fieldKey: const Key('exercise-name-field'),
          label: 'Name',
          controller: _name,
          hint: 'Bench Press',
          autofocus: !_editing,
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Muscle group (optional)',
          controller: _muscle,
          hint: 'Chest',
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: PlanNumberField(label: 'Sets', controller: _sets),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REP TARGET',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    // SelectChip is a shared capture-widgets component (also
                    // used by diet/schedule, outside this batch's scope) with
                    // no press feedback of its own — wrapped locally here
                    // rather than editing the shared widget.
                    children: [
                      PressableScale(
                        child: SelectChip(
                          label: 'Fixed',
                          selected: _mode == RepMode.fixed,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = RepMode.fixed);
                          },
                        ),
                      ),
                      PressableScale(
                        child: SelectChip(
                          label: 'Range',
                          selected: _mode == RepMode.range,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = RepMode.range);
                          },
                        ),
                      ),
                      PressableScale(
                        child: SelectChip(
                          label: 'To failure',
                          selected: _mode == RepMode.toFailure,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = RepMode.toFailure);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_mode != RepMode.toFailure) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PlanNumberField(
                  label: _mode == RepMode.range ? 'Min reps' : 'Reps',
                  controller: _reps,
                ),
              ),
              if (_mode == RepMode.range) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: PlanNumberField(
                    label: 'Max reps',
                    controller: _repsMax,
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RestPicker(
                initialSeconds: _restSeconds,
                onChanged: (v) => _restSeconds = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PlanNumberField(
                label: 'Weight (kg)',
                controller: _weight,
                hint: '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        PillButton(
          label: _editing ? 'Save changes' : 'Add exercise',
          icon: _editing ? Icons.check_rounded : Icons.add_rounded,
          color: TrainColors.ember,
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
class RestPicker extends StatefulWidget {
  const RestPicker({
    required this.initialSeconds,
    required this.onChanged,
    super.key,
  });

  final int initialSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<RestPicker> createState() => _RestPickerState();
}

class _RestPickerState extends State<RestPicker> {
  static const _stepSeconds = 5;
  static const _maxSeconds = 300;

  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem:
            widget.initialSeconds.clamp(0, _maxSeconds) ~/ _stepSeconds,
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
        Text(
          'REST',
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 132,
          decoration: BoxDecoration(
            color: TrainColors.glassStrong,
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
                color: TrainColors.hairline,
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
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      height: 1.1,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
