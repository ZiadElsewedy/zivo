import 'package:flutter/material.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../domain/workout_plan_format.dart';
import 'exercise_sheet.dart';
import 'plan_edit_chrome.dart';

/// The discoverable bulk-rest control — "where's Edit Rest" for the whole
/// plan at once. Shows the value it'll apply so it reads as a real control,
/// not a mystery button.
class DefaultRestRow extends StatelessWidget {
  const DefaultRestRow({required this.seconds, required this.onTap, super.key});

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
              color: const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TrainColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: TrainColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Default rest · ${restLabel(seconds)}',
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      height: 1.1,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
                Text(
                  'Set all',
                  style: TrainType.mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    tracking: 0.06,
                    color: TrainColors.green,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TrainColors.ink4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bulk-rest sheet — the same dark [RestPicker] wheel used for a single
/// exercise's rest, but its result applies to every exercise in the plan at
/// once (see [_WorkoutPlanEditPageState._pickDefaultRest]).
class DefaultRestSheet extends StatefulWidget {
  const DefaultRestSheet({required this.initialSeconds, super.key});

  final int initialSeconds;

  @override
  State<DefaultRestSheet> createState() => _DefaultRestSheetState();
}

class _DefaultRestSheetState extends State<DefaultRestSheet> {
  late int _seconds = widget.initialSeconds;

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'Default rest',
      children: [
        Text(
          'Sets every exercise in this plan to this rest. Editing one exercise '
          'afterward still overrides it individually.',
          style: TrainType.ui(
            size: 13.5,
            weight: FontWeight.w400,
            height: 1.5,
            color: TrainColors.ink2,
          ),
        ),
        const SizedBox(height: 16),
        RestPicker(initialSeconds: _seconds, onChanged: (v) => _seconds = v),
        const SizedBox(height: 22),
        PillButton(
          label: 'Set all',
          icon: Icons.check_rounded,
          color: TrainColors.ember,
          enabled: true,
          onTap: () => Navigator.of(context).pop(_seconds),
        ),
      ],
    );
  }
}
