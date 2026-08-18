import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/today_snapshot.dart';
import 'common.dart';
import 'hue.dart';

/// The single most relevant time-thing — the one place Ember lives on Today.
class NowNextCard extends StatelessWidget {
  const NowNextCard(this.data, {super.key});

  final NowNext data;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.emberWash, AppColors.card],
        stops: [0.0, 0.85],
      ),
      borderColor: AppColors.ember.withValues(alpha: 0.14),
      washShadow: const [
        BoxShadow(
          color: Color(0x0FDC490E),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
        BoxShadow(
          color: Color(0x4DDC490E),
          blurRadius: 34,
          spreadRadius: -18,
          offset: Offset(0, 16),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeaderRow(hue: ZHue.ember, label: data.kind, trailing: data.time),
          const SizedBox(height: AppSpacing.m + 1),
          Text(data.title, style: AppText.cardTitle),
          if (data.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _detail(data.detail),
          ],
        ],
      ),
    );
  }

  // Bold the last clause after the final "·" as the actionable emphasis.
  Widget _detail(String detail) {
    final parts = detail.split(' · ');
    if (parts.length < 2) {
      return Text(detail, style: AppText.body);
    }
    final lead = '${parts.sublist(0, parts.length - 1).join(' · ')} · ';
    final tail = parts.last;
    return Text.rich(
      TextSpan(
        style: AppText.body,
        children: [
          TextSpan(text: lead),
          TextSpan(
            text: tail,
            style: AppText.body.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
