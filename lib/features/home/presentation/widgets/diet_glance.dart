import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'hue.dart';
import '../../../../core/theme/train_tokens.dart';

/// One glance line, like [SpendingGlanceRow] — "2 of 5 meals eaten · 1400
/// kcal left". Values are live from the diet repository.
class DietGlanceRow extends StatelessWidget {
  const DietGlanceRow({
    required this.eaten,
    required this.total,
    required this.kcalLeft,
    required this.kcalEstimated,
    super.key,
  });

  final int eaten;
  final int total;
  final int kcalLeft;

  /// Whether [kcalLeft] rests on AI-estimated figures — shown as the same "~"
  /// the Diet screen uses, so Today never states as fact what Diet marks as a
  /// guess.
  final bool kcalEstimated;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          const HueDot(ZHue.neutral),
          const SizedBox(width: AppSpacing.m - 1),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.amount.copyWith(color: TrainColors.ink),
                children: [
                  TextSpan(text: '$eaten of $total meals eaten'),
                  TextSpan(
                    text: kcalEstimated
                        ? '  ·  ~$kcalLeft kcal left'
                        : '  ·  $kcalLeft kcal left',
                    style: AppText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: TrainColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: TrainColors.ink3,
          ),
        ],
      ),
    );
  }
}
