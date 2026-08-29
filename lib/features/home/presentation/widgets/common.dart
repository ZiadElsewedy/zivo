import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import 'hue.dart';

/// Uppercase section label above each Today block — the handoff's caption:
/// mono, uppercase, wide-tracked, dim. It labels; it never competes
/// (identity §6).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {this.top = AppSpacing.section, super.key});

  final String label;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 11),
      child: Text(
        label.toUpperCase(),
        style: TrainType.caption(
          size: 9.5,
          tracking: 0.2,
          color: const Color(0x4DF4F4F0),
        ),
      ),
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
        Text(
          label.toUpperCase(),
          style: AppText.hueLabel.copyWith(color: hue.text),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(trailing!, style: AppText.meta),
        ],
      ],
    );
  }
}
