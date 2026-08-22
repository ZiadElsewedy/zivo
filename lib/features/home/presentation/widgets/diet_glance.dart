import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'hue.dart';

/// One glance line, like [SpendingGlanceRow] — "2 of 5 meals eaten · 1400
/// kcal left". Values are live from the diet repository.
class DietGlanceRow extends StatelessWidget {
  const DietGlanceRow({
    required this.eaten,
    required this.total,
    required this.kcalLeft,
    super.key,
  });

  final int eaten;
  final int total;
  final int kcalLeft;

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
                style: AppText.amount.copyWith(color: AppColors.ink),
                children: [
                  TextSpan(text: '$eaten of $total meals eaten'),
                  TextSpan(
                    text: '  ·  $kcalLeft kcal left',
                    style: AppText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
        ],
      ),
    );
  }
}
