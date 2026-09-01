import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'hue.dart';
import '../../../../core/theme/train_tokens.dart';

/// One glance line, like [SpendingGlanceRow] — "2 of 5 meals eaten · 1400
/// kcal left". Values are live from the diet repository.
///
/// It measures against the same yardstick the Diet screen does: the user's own
/// daily target when they've set one ("of target"), the day's plan otherwise
/// ("of plan"). Two surfaces quoting the same phrase against different
/// baselines is exactly the kind of quiet disagreement that makes a number
/// untrustworthy, so the baseline is always named.
class DietGlanceRow extends StatelessWidget {
  const DietGlanceRow({
    required this.eaten,
    required this.total,
    required this.kcalLeft,
    required this.kcalEstimated,
    required this.againstTarget,
    super.key,
  });

  final int eaten;
  final int total;

  /// Calories left. Negative when a target has been passed — see
  /// [againstTarget].
  final int kcalLeft;

  /// Whether [kcalLeft] rests on AI-estimated figures — shown as the same "~"
  /// the Diet screen uses, so Today never states as fact what Diet marks as a
  /// guess.
  final bool kcalEstimated;

  /// True when [kcalLeft] is measured against the user's own target rather
  /// than the day's plan total.
  final bool againstTarget;

  /// "1,400 kcal left of target" / "200 kcal over target" / "1,400 kcal left
  /// of plan", with "~" when the figure rests on estimated values.
  String _kcalText() {
    final tilde = kcalEstimated ? '~' : '';
    final baseline = againstTarget ? 'target' : 'plan';
    if (againstTarget && kcalLeft < 0) {
      return '$tilde${-kcalLeft} kcal over $baseline';
    }
    return '$tilde$kcalLeft kcal left of $baseline';
  }

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
                    text: '  ·  ${_kcalText()}',
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
