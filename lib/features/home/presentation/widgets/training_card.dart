import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/today_snapshot.dart';
import 'common.dart';
import 'hue.dart';

/// Today's training — a Pulse card. Start is a Pulse action so Ember stays
/// singular (it belongs to Now/Next).
class TrainingCard extends StatelessWidget {
  const TrainingCard(this.data, {this.onStart, super.key});

  final TrainingToday data;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      wash: AppColors.pulseWash,
      washShadow: const [
        BoxShadow(color: Color(0x0F0A8F63), blurRadius: 4, offset: Offset(0, 2)),
        BoxShadow(
          color: Color(0x420A8F63),
          blurRadius: 34,
          spreadRadius: -18,
          offset: Offset(0, 16),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeaderRow(hue: ZHue.pulse, label: data.label, trailing: data.duration),
          const SizedBox(height: AppSpacing.m + 1),
          Text(data.title, style: AppText.cardTitle),
          const SizedBox(height: 6),
          Text(data.detail, style: AppText.body),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  data.meta,
                  style: AppText.meta.copyWith(color: AppColors.pulseText),
                ),
              ),
              _StartButton(onTap: onStart),
            ],
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pulseText,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.pulse,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Start',
                style: AppText.button.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
