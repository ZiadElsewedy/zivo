import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/progress_comparison.dart';

/// The icon/color/word for a [ProgressVerdict] — shared so the live session's
/// set-level badge and the analysis page's exercise-level badge read as the
/// same visual language.
///
/// On the design handoff's palette: **green means progress**, and a set that
/// went down takes **ember** — the colour the identity doc reserves for the
/// thing that wants your attention. There is no fifth "bad" red: matching a
/// previous set isn't a failure, so it stays neutral ink rather than being
/// coloured at all.
/// Shares its three words with [progressStatusStyle]/[trendToneStyle] — the
/// same `workoutStatusProgressing` / `workoutToneMatched` / `workoutToneDown`
/// keys — so a set-level badge and an exercise-level badge never disagree
/// about what "Down" is called.
(IconData, Color, String) verdictStyle(
  BuildContext context,
  ProgressVerdict verdict,
) => switch (verdict) {
  ProgressVerdict.progressing => (
    Icons.trending_up_rounded,
    TrainColors.green,
    l(context).workoutStatusProgressing,
  ),
  ProgressVerdict.matched => (
    Icons.horizontal_rule_rounded,
    TrainColors.ink4,
    l(context).workoutToneMatched,
  ),
  ProgressVerdict.down => (
    Icons.trending_down_rounded,
    TrainColors.ember,
    l(context).workoutToneDown,
  ),
};
