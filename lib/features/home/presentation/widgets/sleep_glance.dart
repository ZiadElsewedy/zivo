import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../sleep/domain/sleep_night.dart';
import '../../../sleep/presentation/pages/sleep_page.dart';
import '../../../sleep/presentation/sleep_labels.dart';
import 'common.dart';
import 'hue.dart';

/// Last night on Today — one line, with its source.
///
/// Two rules from `docs/SLEEP_SYSTEM.md` that a glance row is especially
/// tempted to break, because it has so little room:
///
/// * **The source travels with the figure.** "7h 12m" alone is the claim ZIVO
///   will not make. If a row is too narrow for both, the row is too narrow.
/// * **It hides rather than showing a zero.** With no night, this section is
///   simply not on Today — the same way the Move ring hides on a host with no
///   step sensor. A `0h 0m` would be a statement about the user's night; an
///   absent section is a statement about the data, and only the second one is
///   true.
class SleepGlanceSection extends StatelessWidget {
  const SleepGlanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final sleep = AppScope.of(context).sleep;
    if (sleep == null) return const SizedBox.shrink();

    return StreamBuilder<List<SleepNight>>(
      stream: sleep.watchNights(),
      initialData: sleep.current,
      builder: (context, snapshot) {
        final nights = snapshot.data ?? const <SleepNight>[];
        SleepNight? last;
        for (final night in nights) {
          if (night.hasData) {
            last = night;
            break;
          }
        }
        if (last == null) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(l(context).sleepTitle),
            _SleepGlanceRow(night: last),
          ],
        );
      },
    );
  }
}

class _SleepGlanceRow extends StatelessWidget {
  const _SleepGlanceRow({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final session = night.main!;
    final delta = sleepDurationDeltaText(context, night);

    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SleepPage())),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            const HueDot(ZHue.iris),
            const SizedBox(width: AppSpacing.m - 1),
            Text(
              sleepDurationText(context, session.asleepDuration),
              style: AppText.amount.copyWith(color: TrainColors.ink),
            ),
            Text(
              '  ·  ',
              style: AppText.amount.copyWith(color: TrainColors.ink3),
            ),
            Flexible(
              child: Text(
                // The source, always. Falls back to the delta only when there
                // is no room for both — never the other way round.
                sleepSourceChipText(context, session.provenance),
                style: AppText.meta.copyWith(color: TrainColors.ink3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: AppSpacing.s),
              Flexible(
                child: Text(
                  delta,
                  style: AppText.meta.copyWith(color: TrainColors.ink4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: TrainColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
