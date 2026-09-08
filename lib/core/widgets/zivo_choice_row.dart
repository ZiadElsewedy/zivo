import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';

/// One option in a "pick exactly one" sheet — the language picker, the theme
/// picker, and anything else that is a short, flat list of mutually exclusive
/// choices.
///
/// Deliberately not a radio button. The selected row is marked by *ink and a
/// check*, which is the iOS Settings pattern and the one this app's two
/// pickers already drew by hand: a control that repeats "this is a choice" in
/// every row is spending pixels on something the sheet's shape already says.
///
/// Shared so the two sheets can't drift — they were the same forty lines
/// twice, and the second copy is how a design system starts having two
/// answers for one question.
class ZivoChoiceRow extends StatelessWidget {
  const ZivoChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The check's hue. Defaults to violet — these sheets are system/meta
  /// surfaces, which is exactly what violet owns (ADR-006 §2).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.rowTitle.copyWith(
                  color: selected ? TrainColors.inkPlain : TrainColors.ink2,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 19,
                color: accent ?? TrainColors.violetGlyph,
              ),
          ],
        ),
      ),
    );
  }
}
