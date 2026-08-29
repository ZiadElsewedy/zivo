import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import 'hue.dart';
import '../../../../core/theme/train_tokens.dart';

/// One glance line, never a chart — awareness on Today, analysis in the module.
/// Values are live from the expense repository.
class SpendingGlanceRow extends StatelessWidget {
  const SpendingGlanceRow({
    required this.todayMinor,
    required this.weekMinor,
    required this.currency,
    this.walletMinor,
    super.key,
  });

  final int todayMinor;
  final int weekMinor;
  final String currency;

  /// What's left in the wallet, if the user has set one up. When present,
  /// this replaces the "this week" stat — the balance is the more actionable
  /// glance-value once a wallet exists; the full week breakdown still lives
  /// inside the Expenses tab.
  final int? walletMinor;

  @override
  Widget build(BuildContext context) {
    final wallet = walletMinor;
    final negative = wallet != null && wallet < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          const HueDot(ZHue.neutral),
          const SizedBox(width: AppSpacing.m - 1),
          _amount(formatAmount(todayMinor), '$currency today', TrainColors.ink),
          Text(
            '  ·  ',
            style: AppText.amount.copyWith(color: TrainColors.ink3),
          ),
          if (wallet != null)
            _amount(
              formatAmount(wallet),
              '$currency left',
              negative ? TrainColors.ember : TrainColors.ink2,
              unitColor: negative
                  ? TrainColors.ember.withValues(alpha: 0.75)
                  : TrainColors.ink3,
            )
          else
            _amount(
              formatAmount(weekMinor),
              '$currency this week',
              TrainColors.ink2,
              unitColor: TrainColors.ink3,
            ),
          const Spacer(),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: TrainColors.ink3,
          ),
        ],
      ),
    );
  }

  Widget _amount(String value, String unit, Color color, {Color? unitColor}) {
    return Text.rich(
      TextSpan(
        style: AppText.amount.copyWith(color: color),
        children: [
          TextSpan(text: '$value '),
          TextSpan(
            text: unit,
            style: AppText.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: unitColor ?? TrainColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
