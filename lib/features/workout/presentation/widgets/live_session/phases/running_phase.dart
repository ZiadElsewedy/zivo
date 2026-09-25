import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/util/parse.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../domain/progression.dart';
import '../../../../domain/rep_target.dart';
import '../../../../domain/weight_unit.dart';
import '../../../workout_labels.dart';
import '../../../controllers/live_session_controller.dart';
import '../../staggered_reveal.dart';
import '../../../../domain/logged_set.dart';
import '../../../../domain/session_exercise.dart';
import '../exercise_swipe.dart';
import '../goal_block.dart';
import '../live_session_format.dart';
import '../set_chips.dart';
import '../set_input.dart';
import 'phase_scaffold.dart';

/// The logging screen — the one you spend the workout on.
///
/// Carries no music slot of its own: the companion is docked below the phase
/// for the whole session (see the page's top-level build), so a track stays
/// controllable from warm-up, logging and rest alike without any phase having
/// to host it.
class RunningPhase extends StatelessWidget {
  const RunningPhase({
    required this.controller,
    required this.onDone,
    required this.onSkip,
    this.onOptions,
    this.onEditSet,
    this.accent,
    super.key,
  });

  /// Opens the current exercise's options (swap, later, sets, skip).
  final VoidCallback? onOptions;

  /// Opens a resolved set for correction (the review sheet).
  final void Function(SessionExercise exercise, LoggedSet set, int position)?
  onEditSet;

  final LiveSessionController controller;

  /// The ambience tint pulled from the current artwork, when there is any.
  final Color? accent;

  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final exercise = controller.session.currentExercise;
    final set = controller.session.currentSet;
    if (exercise == null || set == null) {
      return Center(child: Text(l(context).liveNothingToDo));
    }

    final target = set.target;
    final targetText = target.kind == RepTargetKind.toFailure
        ? null
        : l(context).workoutRepsSpec(repTargetText(context, target));
    final previousSet = controller.previousSetFor(exercise, set);
    final goal = computeGoal(
      target: target,
      targetWeightKg: set.targetWeightKg,
      previous: previousSet,
      muscleGroup: exercise.muscleGroup,
    );
    final liveReps = controller.reps.text.trim();
    final liveWeight = controller.weight.text.trim();
    final carriedWeight = controller.carriedWeightFor(exercise, set);
    final unit = controller.weightUnit;
    // The ± step is equipment-aware, not a hardcoded 2.5: a compound lift
    // steps a plate-pair, an isolation movement the smaller jump, each in the
    // active unit.
    final weightStep = weightStepFor(unit, exercise.muscleGroup);
    final hasAnchors = carriedWeight != null || goal.weightKg != null;

    final canMove = controller.canChangeExercise;

    return RunningScaffold(
      top: [
        // The heading and the set chips move together under a swipe — they
        // are "this exercise"; the steppers below take drags of their own.
        ExerciseSwipe(
          onNext: canMove ? controller.nextExercise : null,
          onPrevious: canMove ? controller.previousExercise : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaggeredReveal(
                index: 0,
                child: ExerciseHeader(
                  exercise,
                  onPrevious: canMove ? controller.previousExercise : null,
                  onNext: canMove ? controller.nextExercise : null,
                  onOptions: onOptions,
                ),
              ),
              const SizedBox(height: 22),
              StaggeredReveal(
                index: 1,
                child: SetChipRow(
                  exercise: exercise,
                  currentSetId: set.id,
                  liveReps: liveReps,
                  liveWeight: liveWeight,
                  unit: unit,
                  onEditSet: onEditSet == null
                      ? null
                      : (s, position) => onEditSet!(exercise, s, position),
                  onAddSet: () => controller.addSet(exercise.id),
                ),
              ),
            ],
          ),
        ),
      ],
      hero: [
        // The hero: the goal card carrying reps × weight, the point of this
        // whole screen — everything above just orients you to it.
        StaggeredReveal(
          index: 2,
          child: GoalBlock(
            lastTimeLabel: formatLastTime(l(context), previousSet, unit),
            goal: goal,
            targetText: targetText,
            intraSessionDelta: intraSessionDeltaLabel(
              strings: l(context),
              previous: controller.previousSetInSession(exercise, set),
              actualReps: parseWhole(controller.reps.text),
              actualWeightKg: controller.typedWeightKg,
              unit: unit,
            ),
            previous: previousSet,
            restSeconds: exercise.restSeconds,
            liveReps: liveReps,
            liveWeight: liveWeight,
            unit: unit,
            accent: accent,
          ),
        ),
        const SizedBox(height: 16),
        StaggeredReveal(
          index: 3,
          child: Column(
            children: [
              Row(
                children: [
                  StepperField(
                    label: l(context).liveReps,
                    controller: controller.reps,
                    step: 1,
                    onChanged: controller.onActualChanged,
                  ),
                  const SizedBox(width: 10),
                  StepperField(
                    label: l(context).liveWeight,
                    controller: controller.weight,
                    step: weightStep,
                    hint: '—',
                    onChanged: controller.onActualChanged,
                    trailing: UnitSelector(
                      unit: unit,
                      onChanged: controller.setUnit,
                    ),
                  ),
                ],
              ),
              // The two load anchors — Last (repeat what you lifted) and Goal
              // (take the recommendation). They read the same carry-forward
              // the prefill does, not just the index-aligned set: on a plan
              // written without loads that alignment is null for every set, so
              // an anchor row keyed only off it would vanish precisely when
              // typing-avoidance is needed most.
              if (hasAnchors) ...[
                const SizedBox(height: AppSpacing.m),
                LoadAnchorRow(
                  last: carriedWeight,
                  goal: goal.weightKg,
                  unit: unit,
                  onPick: (weightKg) {
                    HapticFeedback.selectionClick();
                    controller.weight.text = unit.display(weightKg);
                    controller.onActualChanged();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
      done: StaggeredReveal(
        index: 4,
        child: ActionCluster(onSkip: onSkip, onDone: onDone),
      ),
    );
  }
}
