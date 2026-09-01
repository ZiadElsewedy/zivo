import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../../../core/theme/train_tokens.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../domain/logged_set.dart';
import '../../../../domain/session_exercise.dart';
import '../../../controllers/live_session_controller.dart';
import '../../staggered_reveal.dart';
import '../session_effects.dart';
import '../session_header.dart';
import '../session_review.dart';

/// The end-of-workout screen: what you did, and the one button that commits
/// it.
///
/// The review list is a gate, not a receipt — every resolved set is tappable
/// until Finish, so a skip can be marked actually-done with real numbers and a
/// mistyped actual can be corrected. Nothing here is final until Finish (the
/// §3.4 review-gate pattern, same idea as the AI import's mandatory review).
class CompletedPhase extends StatelessWidget {
  const CompletedPhase({
    required this.controller,
    required this.dayLabel,
    required this.onEditSet,
    required this.onFinish,
    super.key,
  });

  final LiveSessionController controller;
  final String dayLabel;
  final void Function(SessionExercise exercise, LoggedSet set, int position)
  onEditSet;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final elapsed = session.elapsed;
    // Every exercise with at least one resolved (done or skipped) set —
    // deliberately not `doneSetCount > 0`, since an exercise whose only sets
    // were skipped still needs to show up here to be reviewable.
    final reviewedExercises = session.exercises
        .where((e) => e.sets.any((s) => !s.pending))
        .toList();
    return ListView(
      key: const ValueKey('completed-list'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Center(
          child: PhaseEyebrow(
            l(context).liveWorkoutComplete,
            color: TrainColors.green,
            icon: AppIcons.check,
          ),
        ),
        const SizedBox(height: 14),
        const Center(
          child: PopIn(
            child: Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: TrainColors.green,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          dayLabel,
          style: AppText.cardTitle.copyWith(
            fontSize: 24,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${session.completedSetCount} of ${session.totalSets} sets · ${elapsed.inMinutes} min',
          style: AppText.meta.copyWith(color: TrainColors.green),
        ),
        const SizedBox(height: 18),
        for (final (i, exercise) in reviewedExercises.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StaggeredReveal(
              index: i,
              child: ReviewExerciseGroup(
                exercise: exercise,
                onEditSet: (set, position) =>
                    onEditSet(exercise, set, position),
              ),
            ),
          ),
        const SizedBox(height: 14),
        StaggeredReveal(
          index: reviewedExercises.length,
          child: PillButton(
            label: l(context).liveFinish,
            icon: Icons.check_rounded,
            color: TrainColors.green,
            enabled: !controller.isBusy,
            onTap: onFinish,
          ),
        ),
      ],
    );
  }
}
