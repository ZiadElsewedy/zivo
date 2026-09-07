import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../domain/sleep_provenance.dart';
import '../sleep_labels.dart';

/// The provenance chip that travels with **every** sleep figure.
///
/// Not decoration and not optional: a duration shown without its source is
/// precisely the claim this feature exists to refuse (`docs/SLEEP_SYSTEM.md`
/// §11). Wherever a sleep number appears — the hero, the Today glance, a week
/// row's detail — this sits with it.
///
/// It reads as one line: **who** recorded it, then **how**. The colour carries
/// the second half, so a measured night and a typed one are distinguishable
/// before the words are read:
///
/// * measured → violet, the hue this screen owns
/// * recorded (platform, unattributed) → violet, dimmed
/// * logged by you / estimate → neutral ink, no hue
///
/// The hue is deliberately spent on measurement rather than on "sleep": giving
/// a typed guess the same colour as a wrist sensor would undo in one glance
/// what the whole pipeline is for.
class SleepSourceChip extends StatelessWidget {
  const SleepSourceChip({
    required this.provenance,
    this.compact = false,
    super.key,
  });

  final SleepProvenance provenance;

  /// Drops the background and shrinks the type — for a dense row where the
  /// chip would otherwise crowd the figure it belongs to.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final measured = provenance.method.isMeasured;
    final platform = provenance.method == SleepMethod.platformDerived;
    final color = measured
        ? TrainColors.violetGlyph
        : (platform ? TrainColors.violet : TrainColors.ink3);

    final label = Text(
      sleepSourceChipText(context, provenance),
      style: AppText.sectionLabel.copyWith(
        color: color,
        fontSize: compact ? 10 : 11,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (compact) return label;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: measured ? TrainColors.violetWash : TrainColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: label,
    );
  }
}

/// The confidence badge, shown **only where it changes what the reader should
/// think** — beside a low-confidence figure.
///
/// High confidence needs no badge: the source chip already says the night was
/// measured, and decorating good data with a "high confidence" sticker trains
/// people to stop reading the badges. A badge that is always present carries
/// no information.
class SleepConfidenceBadge extends StatelessWidget {
  const SleepConfidenceBadge({required this.confidence, super.key});

  final SleepConfidence confidence;

  @override
  Widget build(BuildContext context) {
    if (confidence == SleepConfidence.high) return const SizedBox.shrink();
    return Text(
      sleepConfidenceLabel(context, confidence),
      style: AppText.sectionLabel.copyWith(
        color: confidence == SleepConfidence.low
            ? TrainColors.ink4
            : TrainColors.ink3,
        fontSize: 10,
      ),
    );
  }
}
