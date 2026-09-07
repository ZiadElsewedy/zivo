import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_session.dart';
import '../sleep_labels.dart';
import 'sleep_source_chip.dart';

/// **The receipt.** Where a night's number came from, what else disagreed, and
/// how much of the night was actually recorded.
///
/// This sheet is what turns "trust us" into something a user can check, and it
/// is cheap to build precisely because the data layer already carries every
/// answer (`docs/SLEEP_SYSTEM.md` §13). It is also the honest place to admit
/// disagreement: two providers thirty minutes apart is a fact about the
/// night, and hiding it behind a single confident figure would be the exact
/// failure the resolver refuses to commit by averaging.
Future<void> showSleepWhySheet(BuildContext context, SleepNight night) {
  return showZivoSheet<void>(
    context: context,
    isScrollControlled: false,
    builder: (_) => _SleepWhySheet(night: night),
  );
}

class _SleepWhySheet extends StatelessWidget {
  const _SleepWhySheet({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final session = night.main;

    return ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: ZivoSheetHandle()),
              const SizedBox(height: AppSpacing.base),
              Text(strings.sleepWhyTitle, style: AppText.cardTitle),
              const SizedBox(height: AppSpacing.m),

              if (session == null)
                Text(
                  strings.sleepNoDataBody,
                  style: AppText.body.copyWith(color: TrainColors.ink2),
                )
              else ...[
                Text(
                  sleepResolutionText(context, night.resolution),
                  style: AppText.body.copyWith(color: TrainColors.ink2),
                ),
                const SizedBox(height: AppSpacing.base),
                SleepSourceChip(provenance: session.provenance),
                const SizedBox(height: AppSpacing.base),

                _Row(
                  label: strings.sleepRecordedBy(
                    sleepProviderName(context, session.provenance),
                  ),
                  value: sleepConfidenceLabel(
                    context,
                    session.provenance.confidence,
                  ),
                ),
                _Row(
                  label: strings.sleepCoverageLabel,
                  value: sleepPercentText(
                    context,
                    session.provenance.completeness,
                  ),
                ),
                _Row(
                  label: strings.sleepDurationLabel,
                  value: sleepDurationText(context, session.asleepDuration),
                ),
                _Row(
                  label: strings.sleepTimeInBedLabel,
                  value: session.timeInBed == null
                      ? strings.sleepEfficiencyUnknown
                      : sleepDurationText(context, session.timeInBed!),
                ),
                _Row(
                  label: strings.sleepEfficiencyLabel,
                  // Null here is a real answer, not a missing one: a source
                  // that does not track time in bed cannot yield an
                  // efficiency, and 100% would be an invention.
                  value: session.efficiency == null
                      ? strings.sleepEfficiencyUnknown
                      : sleepPercentText(context, session.efficiency!),
                ),

                if (session.spansDstChange) ...[
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    strings.sleepSpansDstNote,
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ],

                // Every source that disagreed, and by how much. Listed
                // without a heading because each line is a whole sentence.
                if (night.hasAlternates) ...[
                  const SizedBox(height: AppSpacing.m),
                  Container(height: 1, color: TrainColors.hairline),
                  const SizedBox(height: AppSpacing.m),
                  for (final alternate in night.alternates)
                    _Disagreement(chosen: session, other: alternate),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ),
        Text(value, style: AppText.rowTitle),
      ],
    ),
  );
}

/// One losing source, and by how much it disagreed.
///
/// Shown rather than suppressed: the size of the disagreement is information
/// about how much to trust the headline figure, and it is exactly what an
/// average would have destroyed.
class _Disagreement extends StatelessWidget {
  const _Disagreement({required this.chosen, required this.other});

  final SleepSession chosen;
  final SleepSession other;

  @override
  Widget build(BuildContext context) {
    final delta = other.startAt.difference(chosen.startAt).abs();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        l(context).sleepDisagreement(
          sleepProviderName(context, other.provenance),
          ltrFor(context, sleepDurationText(context, delta)),
        ),
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      ),
    );
  }
}
