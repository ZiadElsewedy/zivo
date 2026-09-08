import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import 'hue.dart';

/// Uppercase section label above each Today block — the handoff's caption:
/// mono, uppercase, wide-tracked, dim. It labels; it never competes
/// (identity §6).
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.label, {
    this.trailing,
    this.top = AppSpacing.section,
    super.key,
  });

  final String label;

  /// A qualifier on the leading edge's opposite side, in the same caption
  /// face. Exists for the case where a Today section is showing something
  /// that is **not** from today — the sleep glance, when the most recent
  /// night is older than last night. Today is a today surface, so a section
  /// on it that carries an older figure has to say so somewhere, and the
  /// glance row itself is already full (a duration that cannot fit its source
  /// is a duration this app does not show).
  final String? trailing;

  final double top;

  @override
  Widget build(BuildContext context) {
    final style = TrainType.caption(
      size: 9.5,
      tracking: 0.2,
      color: TrainColors.inkAt(0.3),
    );
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 11),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: style),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ],
        ],
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
