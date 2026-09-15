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
    this.badge,
    this.last = false,
  });

  /// The key on the tappable row — sheets give each route a stable name.
  final Key routeKey;
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  /// An optional marker beside the label — e.g. "Recommended" — for the one
  /// route worth nudging toward. Null on every ordinary route.
  final String? badge;
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
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(icon, size: 19, color: TrainColors.ink2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (badge == null)
                        Text(label, style: AppText.rowTitle)
                      else
                        Row(
                          children: [
                            Flexible(
                              child: Text(label, style: AppText.rowTitle),
                            ),
                            const SizedBox(width: 8),
                            _RecommendedBadge(label: badge!),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                  ),
                ),
                Icon(
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

/// A small green pill that marks the one route worth nudging toward — green
/// reads as "go this way" without needing a second meaning.
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TrainColors.greenWash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppText.meta.copyWith(
          color: TrainColors.green,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.6,
          height: 1.0,
        ),
      ),
    );
  }
}
