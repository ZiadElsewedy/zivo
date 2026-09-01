import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/planned_exercise.dart';
import '../../../domain/workout_plan_format.dart';
import '../staggered_reveal.dart';
import 'plan_edit_chrome.dart';
import '../../workout_format.dart';
import '../../controllers/plan_edit_controller.dart';

/// A collapsible day tile — collapsed shows just the header (day title +
/// exercise count); tapping the header springs it open to reveal the
/// exercise list (notes, rows, "Add exercise"). Exists so editing a plan
/// with many days doesn't mean scrolling past every prior day's full
/// exercise list to reach the last one — collapsed, each day is one glance.
///
/// Multiple days can be open at once (deliberately not a forced accordion —
/// useful when cross-referencing two days while editing, e.g. copying a
/// rest value). Expand state lives in this State object, keyed by the
/// caller on the day's stable id ([DayDraft.id]), so it survives parent
/// rebuilds (editing/removing a DIFFERENT day, or an exercise within this
/// one) without collapsing back — re-expanding after an edit would be a
/// regression, not a feature.
class DayCard extends StatefulWidget {
  const DayCard({
    required this.day,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onEditExercise,
    required this.onRemoveExercise,
    required this.onReorderExercise,
    required this.removingExerciseIds,
    this.initiallyExpanded = false,
    super.key,
  });

  final DayDraft day;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddExercise;
  final void Function(int exerciseIndex) onEditExercise;
  final void Function(int exerciseIndex) onRemoveExercise;
  final void Function(int oldIndex, int newIndex) onReorderExercise;

  /// Exercise ids mid-collapse — see [_WorkoutPlanEditPageState._removeExercise].
  final Set<String> removingExerciseIds;

  /// Only meaningful the first time this State is created for a given key —
  /// a day the caller just added (see `_WorkoutPlanEditPageState._addDay`)
  /// starts open, since the user is clearly about to add exercises to it;
  /// every other day starts collapsed.
  final bool initiallyExpanded;

  @override
  State<DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<DayCard> with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.initiallyExpanded ? 1 : 0,
  );

  void _toggle() {
    final target = _expanded ? 0.0 : 1.0;
    setState(() => _expanded = !_expanded);
    if (reducedMotion(context)) {
      _controller.value = target;
    } else {
      // Critically damped, no bounce — this is a disclosure, not a
      // momentum-driven gesture. Always retargets from the controller's
      // live value, so tapping again mid-animation reverses smoothly
      // instead of jumping.
      _controller.springTo(target, spring: AppSprings.standard);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final count = day.exercises.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableScale(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Day ${day.slot} · ${day.label}',
                            style: TrainType.ui(
                              size: 15,
                              weight: FontWeight.w600,
                              height: 1.1,
                              color: TrainColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$count exercise${count == 1 ? '' : 's'}',
                            style: TrainType.mono(
                              size: 10.5,
                              tracking: 0.06,
                              color: TrainColors.ink4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform.rotate(
                        angle: _controller.value * math.pi,
                        child: child,
                      ),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: TrainColors.ink4,
                      ),
                    ),
                    PressableScale(
                      child: IconButton(
                        onPressed: widget.onRemoveDay,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: TrainColors.ink4,
                        ),
                        splashRadius: 20,
                        tooltip: 'Remove day',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Fully collapsed and at rest — skip the subtree entirely
              // rather than just squashing it to zero height, so a
              // collapsed day's exercises are genuinely absent (not
              // present-but-invisible/still-hit-testable). Gated on
              // `!_controller.isAnimating`, not an exact `value == 0` check
              // — a settled SpringSimulation can land at a tiny residual
              // (within its tolerance) rather than precisely 0.
              if (!_expanded && !_controller.isAnimating) {
                return const SizedBox.shrink();
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _controller.value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day.notes != null && day.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      day.notes!,
                      style: TrainType.mono(
                        size: 10.5,
                        tracking: 0.06,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ),
                if (day.exercises.isNotEmpty)
                  ReorderableListView.builder(
                    // Nested inside the page's own scrollable — sizes
                    // itself to its (typically short) exercise list rather
                    // than trying to scroll independently.
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) =>
                        liftProxyDecorator(child, animation, radius: 14),
                    onReorderStart: (_) => HapticFeedback.selectionClick(),
                    onReorderEnd: (_) => HapticFeedback.lightImpact(),
                    onReorderItem: widget.onReorderExercise,
                    itemCount: day.exercises.length,
                    itemBuilder: (context, ei) {
                      final exercise = day.exercises[ei];
                      final removing = widget.removingExerciseIds.contains(
                        exercise.id,
                      );
                      final reduced = reducedMotion(context);
                      return Padding(
                        key: ValueKey(exercise.id),
                        padding: const EdgeInsets.only(top: 10),
                        // Same collapse-before-remove / stagger-in pair as
                        // the day list above (see its comment).
                        child: AnimatedSize(
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                          alignment: Alignment.topCenter,
                          child: AnimatedOpacity(
                            opacity: removing ? 0 : 1,
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            child: removing
                                ? const SizedBox(width: double.infinity)
                                : StaggeredReveal(
                                    index: ei,
                                    child: ReorderableDelayedDragStartListener(
                                      index: ei,
                                      child: ExerciseRow(
                                        exercise: exercise,
                                        onEdit: () => widget.onEditExercise(ei),
                                        onRemove: () =>
                                            widget.onRemoveExercise(ei),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 10),
                PlanAddButton(
                  label: 'Add exercise',
                  onTap: widget.onAddExercise,
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One exercise within a day card — tapping it opens the exercise sheet
/// pre-filled for editing in place; the trailing X stays a separate, direct
/// remove action.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    required this.exercise,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

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
              color: TrainColors.glassStrong,
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
                        style: TrainType.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          height: 1.5,
                          color: TrainColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _setSpecLabel(exercise),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.mono(
                          size: 10.5,
                          tracking: 0.06,
                          color: TrainColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                PressableScale(
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: TrainColors.ink4,
                    ),
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
      if (first.targetWeightKg != null)
        '${trimWeight(first.targetWeightKg!)}kg',
      'rest ${restLabel(first.restSeconds)}',
    ];
    return parts.join(' · ');
  }
}
