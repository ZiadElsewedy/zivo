import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/live_session.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';

/// What happens to the day that was DUE when another one is trained instead.
///
/// The rotation advances past whatever was actually trained
/// ([WorkoutPlan.advanceToAfterDay]), so training out of order costs the due
/// day its turn unless something puts it back — which is the whole difference
/// between these two.
enum ChangeWorkoutMode {
  /// The due day and the picked one trade places in the cycle
  /// ([WorkoutPlan.swapDays]): the picked day is trained now and the due day
  /// comes up next, so a cycle meant to cover the whole body still does.
  swap,

  /// The picked day is trained and the due day simply loses this cycle — the
  /// original behaviour, kept for the days you genuinely want to drop.
  skip,
}

/// The result of picking from the change-workout sheet: the [day] to train
/// instead, what to do with the day that was due ([mode]), plus the plan's
/// active [resumable] session when that day is actually the one already under
/// way.
class ChangeWorkoutSelection {
  const ChangeWorkoutSelection({
    required this.day,
    this.mode = ChangeWorkoutMode.swap,
    this.resumable,
  });

  final WorkoutDay day;
  final ChangeWorkoutMode mode;
  final LiveSession? resumable;

  bool get swaps => mode == ChangeWorkoutMode.swap;
}

/// "Change Workout" — every day of the split in one sheet, so the user can
/// train something other than today's scheduled rotation entry. The cursor's
/// day is marked "Next up"; a day with an active/paused session reads as
/// "Resume". Popping with a [ChangeWorkoutSelection] lets the caller start
/// that session directly.
///
/// The [ChangeWorkoutMode] toggle above the list is the sheet's second
/// question: swapping (the default) keeps the cycle whole, skipping drops the
/// due day. It is hidden when there is nothing to trade with — a split of one
/// day, or no day due.
Future<ChangeWorkoutSelection?> showChangeWorkoutSheet(
  BuildContext context, {
  required WorkoutPlan plan,
  LiveSession? activeSession,
}) {
  return showZivoSheet<ChangeWorkoutSelection>(
    context: context,
    builder: (_) => ZivoSheetSurface(
      child: _ChangeWorkoutSheet(plan: plan, activeSession: activeSession),
    ),
  );
}

class _ChangeWorkoutSheet extends StatefulWidget {
  const _ChangeWorkoutSheet({required this.plan, this.activeSession});

  final WorkoutPlan plan;
  final LiveSession? activeSession;

  @override
  State<_ChangeWorkoutSheet> createState() => _ChangeWorkoutSheetState();
}

class _ChangeWorkoutSheetState extends State<_ChangeWorkoutSheet> {
  /// Swap by default: it is the choice that loses nothing, and the one the
  /// rotation was built to assume.
  ChangeWorkoutMode _mode = ChangeWorkoutMode.swap;

  void _setMode(ChangeWorkoutMode mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
    final due = plan.nextDay;
    final canSwap = due != null && days.length > 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: ZivoSheetHandle()),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                l(context).workoutChangeWorkout,
                style: AppText.cardTitle.copyWith(fontSize: 19),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                plan.name,
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
            ),
            if (canSwap) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _ModeToggle(mode: _mode, onChanged: _setMode),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  _mode == ChangeWorkoutMode.swap
                      ? l(context).workoutChangeSwapNote(due.label)
                      : l(context).workoutChangeSkipNote(due.label),
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: days.length,
                itemBuilder: (context, i) {
                  final day = days[i];
                  final active = widget.activeSession;
                  final resumable = active != null && active.dayId == day.id
                      ? active
                      : null;
                  final isNext = due?.id == day.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: PressableScale(
                      child: Material(
                        color: isNext
                            ? TrainColors.raisedStrong
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(
                            ChangeWorkoutSelection(
                              day: day,
                              mode: _mode,
                              resumable: resumable,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    day.label,
                                    style: AppText.rowTitle.copyWith(
                                      color: TrainColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (isNext)
                                  _Badge(
                                    label: l(context).workoutNextUp,
                                    color: TrainColors.green,
                                  )
                                else if (resumable != null)
                                  _Badge(
                                    label: l(context).workoutInProgress,
                                    color: TrainColors.amber,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Swap / Skip — two segments in one hairlined trough, the selected one filled
/// green because this is a training-state decision (hue discipline).
///
/// Deliberately NOT a step of its own: picking a day still starts it on one
/// tap, and this only answers "what happens to the day it displaced."
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final ChangeWorkoutMode mode;
  final ValueChanged<ChangeWorkoutMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TrainColors.hairlineStrong),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              key: const Key('change-mode-swap'),
              label: l(context).workoutChangeSwap,
              selected: mode == ChangeWorkoutMode.swap,
              onTap: () => onChanged(ChangeWorkoutMode.swap),
            ),
          ),
          Expanded(
            child: _ModeSegment(
              key: const Key('change-mode-skip'),
              label: l(context).workoutChangeSkip,
              selected: mode == ChangeWorkoutMode.skip,
              onTap: () => onChanged(ChangeWorkoutMode.skip),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? TrainColors.greenWash : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? TrainColors.green.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AppText.meta.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? TrainColors.green : TrainColors.ink3,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: AppText.meta.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color == TrainColors.green
              ? TrainColors.green
              : TrainColors.amber,
        ),
      ),
    );
  }
}
