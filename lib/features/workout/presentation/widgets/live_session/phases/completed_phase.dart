import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../../../core/theme/train_tokens.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../domain/analytics/workout_analytics.dart';
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
    // PRs THIS session set, versus the split's prior history (excludes the
    // current session, per the controller). Derived, never stored — and the
    // engine only counts a strict beat, so it can't celebrate a non-PR.
    final newPrs = detectNewPrs(
      session: session,
      priorSessions: controller.pastSessions,
    );
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
        if (newPrs.isNotEmpty) ...[
          _PrCelebration(prs: newPrs),
          const SizedBox(height: 16),
        ],
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

/// The just-earned PRs, celebrated before the review list — one of the most
/// visible pieces of progress feedback (product brief §5, §10). Each line is
/// the exercise and the record set; the copy is deliberately light.
class _PrCelebration extends StatelessWidget {
  const _PrCelebration({required this.prs});

  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    // Collapse to at most one line per exercise — the heaviest-weight record
    // reads best, and three trophies for one lift is noise.
    final byExercise = <String, PrRecord>{};
    for (final pr in prs) {
      final existing = byExercise[pr.exerciseId];
      if (existing == null || pr.kind.index < existing.kind.index) {
        byExercise[pr.exerciseId] = pr;
      }
    }
    final lines = byExercise.values.toList();
    return PopIn(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              TrainColors.amber.withValues(alpha: 0.18),
              TrainColors.amber.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TrainColors.amber.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.trophy, size: 18, color: TrainColors.amber),
                const SizedBox(width: 8),
                Text(
                  l(context).livePrsTitle,
                  style: AppText.rowTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TrainColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final pr in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${pr.name} — ${_prSetLine(pr)}',
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _prSetLine(PrRecord pr) {
    final w = pr.weightKg;
    if (w == null) return '${pr.reps} reps';
    final weight = w.truncateToDouble() == w
        ? w.toStringAsFixed(0)
        : w.toStringAsFixed(1);
    return '${weight}kg × ${pr.reps}';
  }
}
