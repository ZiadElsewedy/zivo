import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import 'hue.dart';

/// One glance line, never a chart — awareness on Today, analysis in the module.
/// Values are live from the expense repository.
class SpendingGlanceRow extends StatelessWidget {
  const SpendingGlanceRow({
    required this.todayMinor,
    required this.weekMinor,
    required this.currency,
    super.key,
  });

  final int todayMinor;
  final int weekMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          const HueDot(ZHue.solar),
          const SizedBox(width: AppSpacing.m - 1),
          _amount(formatAmount(todayMinor), '$currency today', AppColors.ink),
          Text('  ·  ', style: AppText.amount.copyWith(color: AppColors.ink3)),
          _amount(
            formatAmount(weekMinor),
            '$currency this week',
            AppColors.solarText,
            unitColor: AppColors.solarText.withValues(alpha: 0.75),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
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
              color: unitColor ?? AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
