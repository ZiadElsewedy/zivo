import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'hue.dart';

/// Uppercase section label above each Today block.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {this.top = AppSpacing.section, super.key});

  final String label;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: AppSpacing.m, left: 2),
      child: Text(label.toUpperCase(), style: AppText.sectionLabel),
    );
  }
}

/// A bright, lifted card. Optionally carries a soft hue wash for its area.
class ZCard extends StatelessWidget {
  const ZCard({required this.child, this.wash, this.washShadow, super.key});

  final Widget child;
  final Color? wash;
  final List<BoxShadow>? washShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: wash ?? AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: washShadow ?? AppShadows.card,
      ),
      child: child,
    );
  }
}

/// Card header: hue dot + uppercase hue label + right-aligned time.
class CardHeaderRow extends StatelessWidget {
  const CardHeaderRow({
    required this.hue,
    required this.label,
    this.trailing,
    super.key,
  });

  final ZHue hue;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HueDot(hue),
        const SizedBox(width: AppSpacing.s),
        Text(label.toUpperCase(), style: AppText.hueLabel.copyWith(color: hue.text)),
        if (trailing != null) ...[
          const Spacer(),
          Text(trailing!, style: AppText.meta),
        ],
      ],
    );
  }
}
