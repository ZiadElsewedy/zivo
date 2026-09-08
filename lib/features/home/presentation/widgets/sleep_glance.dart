import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../sleep/domain/sleep_night.dart';
import '../../../sleep/domain/sleep_window.dart';
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

        // Today is a today surface, and this row may be showing a night from
        // several days ago — the app cannot make the user wear their watch.
        // An undated figure under an undated heading on a page called Today
        // reads as this morning's, which is how a perfectly correct number
        // becomes a false statement.
        final age = SleepWindow.ageInDays(last, DateTime.now());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              l(context).sleepTitle,
              trailing: age > 1 ? l(context).sleepNightsAgo(age) : null,
            ),
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
              maxLines: 1,
              softWrap: false,
              style: AppText.amount.copyWith(color: TrainColors.ink),
            ),
            Text(
              '  ·  ',
              style: AppText.amount.copyWith(color: TrainColors.ink3),
            ),
            // The source, and only the source. The target delta was here too
            // and the row could not hold both — on a 402pt screen in Arabic
            // BOTH ellipsised, which hid the method and left a duration with
            // no provenance. That is the one thing this row may not do, so the
            // delta went back to the Sleep page where it has room.
            Flexible(
              child: Text(
                sleepSourceChipText(context, session.provenance),
                style: AppText.meta.copyWith(color: TrainColors.ink3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
