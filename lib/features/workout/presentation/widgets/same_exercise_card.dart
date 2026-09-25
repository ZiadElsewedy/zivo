import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/identity/exercise_merge.dart';

/// "Same exercise?" — the question the identity migration leaves for the
/// user (ADR-017): two exercises whose names say they might be one movement
/// but can't prove it. One answer merges their history, the other stops the
/// pair being asked about again.
///
/// Also carries the undo for a merge just made, because a merge is only safe
/// to offer in one tap if it is just as easy to take back.
class SameExerciseCard extends StatelessWidget {
  const SameExerciseCard({
    this.suggestion,
    this.justMerged,
    required this.onMerge,
    required this.onKeepSeparate,
    required this.onUndo,
    super.key,
  });

  /// The pair to ask about, or null when only the undo is showing.
  final MergeSuggestion? suggestion;

  /// The merge just made, while its undo is still on offer.
  final MergeSuggestion? justMerged;

  final VoidCallback onMerge;
  final VoidCallback onKeepSeparate;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final ask = suggestion;
    final merged = justMerged;
    return TrainCard(
      key: const Key('same-exercise-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (merged != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.workoutSameExerciseMerged(
                      isolate(merged.merge.name),
                      isolate(merged.keep.name),
                    ),
                    style: AppText.meta.copyWith(color: TrainColors.ink2),
                  ),
                ),
                TextButton(
                  key: const Key('same-exercise-undo'),
                  onPressed: onUndo,
                  child: Text(
                    strings.workoutUndo,
                    style: AppText.meta.copyWith(
                      color: TrainColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          if (merged != null && ask != null) const SizedBox(height: 14),
          if (ask != null) ...[
            Text(
              strings.workoutSameExerciseTitle,
              style: AppText.cardTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              strings.workoutSameExerciseBody(
                isolate(ask.merge.name),
                isolate(ask.keep.name),
              ),
              style: AppText.body.copyWith(color: TrainColors.ink2),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TrainGhostButton(
                    key: const Key('same-exercise-keep'),
                    label: strings.workoutSameExerciseKeep,
                    mono: false,
                    height: 46,
                    onTap: onKeepSeparate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TrainPrimaryButton(
                    key: const Key('same-exercise-merge'),
                    label: strings.workoutSameExerciseMerge,
                    // Green, not ember: this is a training-data decision,
                    // not the screen's one committing action (hue rule).
                    color: TrainColors.green,
                    labelColor: TrainColors.base,
                    height: 46,
                    glowAlpha: 0,
                    onTap: onMerge,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
