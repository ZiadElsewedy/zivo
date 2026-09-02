import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';

/// One row in an "Add a plan" sheet — an icon, a label, a one-line detail, and
/// a chevron. Shared by the diet and workout add-plan sheets so a route reads
/// the same whichever plan it adds.
///
/// Differentiated by icon, not by colour — a hue here would have to mean
/// something, and "dictation" isn't a hue (identity §3).
class AddPlanRouteTile extends StatelessWidget {
  const AddPlanRouteTile({
    super.key,
    required this.routeKey,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.last = false,
  });

  /// The key on the tappable row — sheets give each route a stable name.
  final Key routeKey;
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 9),
      child: TrainCard(
        radius: 18,
        padding: EdgeInsets.zero,
        child: InkWell(
          key: routeKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(icon, size: 19, color: TrainColors.ink2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.rowTitle),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TrainColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
