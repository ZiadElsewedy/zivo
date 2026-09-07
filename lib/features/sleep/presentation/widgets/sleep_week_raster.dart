import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_targets.dart';
import 'sleep_axis.dart';
import 'sleep_bar.dart';

/// **The raster.** Seven nights, one shared local-time axis, one row each.
///
/// This is the chart the whole weekly view exists for, and it is deliberately
/// not a bar chart of durations. A duration chart answers "how long did I
/// sleep" seven times; a raster answers the question the user actually has,
/// which is *"is my sleep drifting?"* — and answers it pre-verbally. A
/// schedule sliding later shows up as a staircase of bars stepping right, and
/// no amount of staring at seven durations reveals that.
///
/// It is the standard chronobiology plot for exactly this reason, and the
/// design rules that make it work are all about refusing to normalise:
///
/// * **One axis for all seven rows.** Per-row scaling would fill each row and
///   destroy the comparison.
/// * **A missing night is an empty row with a hairline** — never a zero-height
///   bar, which reads as "slept nothing".
/// * **Fill encodes method** ([SleepBarFill]), so a week of typed entries can
///   never be mistaken for a week of measurement.
/// * **Target lines are drawn behind, not scored.** Adherence becomes visible;
///   it does not become a grade.
class SleepWeekRaster extends StatelessWidget {
  const SleepWeekRaster({
    required this.nights,
    this.targets,
    this.onTapNight,
    super.key,
  });

  /// Seven sleep-days, oldest first, gaps included as empty nights.
  final List<SleepNight> nights;

  final SleepTargets? targets;
  final void Function(SleepNight night)? onTapNight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // Reserves the weekday-label gutter, which sits on the leading
          // edge — the right one in Arabic.
          padding: const EdgeInsetsDirectional.only(start: _labelWidth),
          child: const SleepAxisLabels(),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final night in nights)
          _RasterRow(
            night: night,
            targets: targets,
            onTap: onTapNight == null ? null : () => onTapNight!(night),
          ),
      ],
    );
  }

  static const double _labelWidth = 34;
}

class _RasterRow extends StatelessWidget {
  const _RasterRow({required this.night, this.targets, this.onTap});

  final SleepNight night;
  final SleepTargets? targets;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasData = night.hasData;
    return Semantics(
      button: onTap != null,
      label: _semanticLabel(context),
      child: GestureDetector(
        onTap: hasData ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: SleepWeekRaster._labelWidth,
                child: Text(
                  formatWeekdayShort(context, night.sleepDay),
                  style: AppText.sectionLabel.copyWith(
                    color: hasData ? TrainColors.ink3 : TrainColors.ink4,
                    fontSize: 10,
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SleepAxisGrid(
                          targetBedtimeMinutes: targets?.bedtimeMinutes,
                          targetWakeMinutes: targets?.wakeMinutes,
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: SleepBar(
                            night: night,
                            height: 14,
                            // A five-minute notch in a week row would be one
                            // pixel and read as a rendering fault.
                            showInterruptions: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Screen readers get the sentence, not the picture — the raster's meaning
  /// is entirely spatial, so it has to be restated in words.
  String _semanticLabel(BuildContext context) {
    final strings = l(context);
    final weekday = formatWeekdayFull(context, night.sleepDay);
    if (!night.hasData) return '$weekday: ${strings.sleepNoData}';
    return '$weekday: ${night.main!.asleepDuration.inHours}h';
  }
}
