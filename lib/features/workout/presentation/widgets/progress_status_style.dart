import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../domain/analytics/exercise_analysis.dart';
import '../../domain/analytics/workout_analytics.dart';

/// The ONE place a progression direction (or a session-to-session tone) gets
/// its word + colour + icon, so the Analysis hub, the exercise detail page and
/// any future surface all read the five directions the same way. Green means
/// progress; ember is the attention colour (identity reserves it for the thing
/// that wants your eye); amber is the softer "flat / stalled"; neutral ink for
/// "holding". There is deliberately no red — a flat lift is not a failure.
class ProgressStatusStyle {
  const ProgressStatusStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

ProgressStatusStyle progressStatusStyle(ProgressStatus s) => switch (s) {
      ProgressStatus.progressing =>
        const ProgressStatusStyle('Progressing', TrainColors.green, AppIcons.trendUp),
      ProgressStatus.maintaining =>
        const ProgressStatusStyle('Holding', TrainColors.ink2, AppIcons.minus),
      ProgressStatus.plateauing =>
        const ProgressStatusStyle('Plateaued', TrainColors.amber, AppIcons.minus),
      ProgressStatus.regressing =>
        const ProgressStatusStyle('Trending down', TrainColors.ember, AppIcons.trendDown),
      ProgressStatus.building =>
        const ProgressStatusStyle('Building', TrainColors.ink4, AppIcons.analysis),
    };

/// The tone of one session versus the previous one — a slightly different
/// vocabulary from the overall direction (a single step "improves"; a lift
/// "progresses").
ProgressStatusStyle trendToneStyle(ExerciseTrendTone t) => switch (t) {
      ExerciseTrendTone.improved =>
        const ProgressStatusStyle('Improved', TrainColors.green, AppIcons.trendUp),
      ExerciseTrendTone.maintained =>
        const ProgressStatusStyle('Matched', TrainColors.ink2, AppIcons.minus),
      ExerciseTrendTone.mixed =>
        const ProgressStatusStyle('Mixed', TrainColors.amber, AppIcons.analysis),
      ExerciseTrendTone.declined =>
        const ProgressStatusStyle('Down', TrainColors.ember, AppIcons.trendDown),
    };
