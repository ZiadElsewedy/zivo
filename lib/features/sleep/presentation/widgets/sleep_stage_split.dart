import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_session.dart';
import '../../domain/sleep_stage_breakdown.dart';
import '../sleep_labels.dart';

/// **What the night was made of** — deep, REM and light, as one proportional
/// bar with a row per stage under it.
///
/// The data has been in the pipeline since the beginning: the sessionizer
/// normalises both platforms' stage vocabularies, the resolver *prefers* a
/// staged night over an unstaged one, and the codec persists every segment.
/// Nothing had ever drawn it, so the app was ranking on detail it then threw
/// away. This is where it lands.
///
/// Two rules the widget cannot be made to break:
///
/// * **It renders a [SleepStageBreakdown] or it renders nothing.** The
///   breakdown is null whenever the source did not grade the night, and there
///   is no path here that derives shares from a duration.
/// * **A stage with no recorded time gets no row.** Zero REM is a clinical
///   claim; a missing segment is not evidence for it, so the stage is simply
///   absent from the list rather than shown as `0m`.
class SleepStageSplit extends StatelessWidget {
  const SleepStageSplit({
    required this.breakdown,
    required this.sessionDuration,
    this.barHeight = 12,
    super.key,
  });

  final SleepStageBreakdown breakdown;

  /// The whole session, so partial staging can be declared rather than
  /// silently presented as the full night.
  final Duration sessionDuration;

  final double barHeight;

  /// Below this share of the session, the staging is announced as partial.
  static const double _wholeNightThreshold = 0.95;

  @override
  Widget build(BuildContext context) {
    final parts = breakdown.gradedParts;
    if (parts.isEmpty) return const SizedBox.shrink();

    final staged = breakdown.stagedTotal;
    final coversWholeNight =
        sessionDuration.inSeconds <= 0 ||
        staged.inSeconds / sessionDuration.inSeconds >= _wholeNightThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageBar(parts: parts, height: barHeight),
        const SizedBox(height: AppSpacing.base),
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _StageRow(
            stage: parts[i].$1,
            duration: parts[i].$2,
            share: breakdown.shareOf(parts[i].$1),
          ),
        ],
        if (!coversWholeNight) ...[
          const SizedBox(height: AppSpacing.m),
          Text(
            l(context).sleepStagesPartial(
              sleepDurationText(context, staged),
            ),
            style: AppText.meta.copyWith(color: TrainColors.ink4),
          ),
        ],
      ],
    );
  }
}

/// The proportional bar. Segments are laid out by [Expanded] flex on the
/// stages' own seconds, so the bar is the arithmetic — there is no separate
/// rounding step that could make it disagree with the rows beneath it.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.parts, required this.height});

  final List<(SleepStage, Duration)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                // Seconds, not minutes: a 40-second stage run would otherwise
                // flex at zero and collapse the segment out of a bar it is
                // genuinely part of.
                flex: parts[i].$2.inSeconds.clamp(1, 1 << 30),
                child: ColoredBox(color: sleepStageColor(parts[i].$1)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.duration,
    required this.share,
  });

  final SleepStage stage;
  final Duration duration;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final percent = share;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: sleepStageColor(stage),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Text(
            sleepStageLabel(context, stage),
            style: AppText.body.copyWith(color: TrainColors.ink2),
          ),
        ),
        if (percent != null) ...[
          Text(
            sleepPercentText(context, percent),
            style: TrainType.mono(size: 13, color: TrainColors.ink3),
          ),
          const SizedBox(width: AppSpacing.m),
        ],
        Text(
          ltrFor(context, sleepDurationText(context, duration)),
          style: TrainType.mono(size: 13.5, color: TrainColors.ink),
        ),
      ],
    );
  }
}

/// The ramp, resolved. Kept beside the widget that draws it so the legend, the
/// bar and the weekly composition all read one table.
Color sleepStageColor(SleepStage stage) => switch (stage) {
  SleepStage.deep => TrainColors.sleepStageDeep,
  SleepStage.rem => TrainColors.sleepStageRem,
  SleepStage.light => TrainColors.sleepStageLight,
  SleepStage.awake => TrainColors.hairlineStrong,
  _ => TrainColors.sleepStageUnknown,
};
