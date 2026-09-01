import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/util/parse.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../domain/progression.dart';
import '../../../../domain/rep_target.dart';
import '../../../../domain/workout_plan_format.dart';
import '../../../controllers/live_session_controller.dart';
import '../../staggered_reveal.dart';
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
    this.accent,
    super.key,
  });

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
        : '${repTargetLabel(target)} reps';
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

    return RunningScaffold(
      top: [
        StaggeredReveal(index: 0, child: ExerciseHeader(exercise)),
        const SizedBox(height: 22),
        StaggeredReveal(
          index: 1,
          child: SetChipRow(
            exercise: exercise,
            currentSetId: set.id,
            liveReps: liveReps,
            liveWeight: liveWeight,
          ),
        ),
      ],
      hero: [
        // The hero: the goal card carrying reps × weight, the point of this
        // whole screen — everything above just orients you to it.
        StaggeredReveal(
          index: 2,
          child: GoalBlock(
            lastTimeLabel: formatLastTime(l(context), previousSet),
            goal: goal,
            targetText: targetText,
            intraSessionDelta: intraSessionDeltaLabel(
              strings: l(context),
              previous: controller.previousSetInSession(exercise, set),
              actualReps: parseWhole(controller.reps.text),
              actualWeightKg: parseDecimal(controller.weight.text),
            ),
            previous: previousSet,
            restSeconds: exercise.restSeconds,
            liveReps: liveReps,
            liveWeight: liveWeight,
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
                    label: l(context).liveWeightKg,
                    controller: controller.weight,
                    step: 2.5,
                    hint: '—',
                    onChanged: controller.onActualChanged,
                  ),
                ],
              ),
              // One-tap load decisions — the last weight as "same", or nudge
              // it by the stepper's own 2.5kg increment — so the common cases
              // ("same again", "go up") never need typing or stepping.
              //
              // Reads the same carry-forward the prefill does, rather than
              // only the index-aligned previous set: on a plan written without
              // loads that alignment is null for every set, so this row — the
              // whole point of which is "don't type the weight" — used to
              // vanish precisely when it was needed most.
              if (carriedWeight != null) ...[
                const SizedBox(height: AppSpacing.m),
                QuickWeightRow(
                  baseWeight: carriedWeight,
                  stepKg: 2.5,
                  onPick: (weight) {
                    HapticFeedback.selectionClick();
                    controller.weight.text = trimWeight(weight);
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
