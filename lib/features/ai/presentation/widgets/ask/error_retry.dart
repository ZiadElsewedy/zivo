import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../l10n/l10n.dart';

/// Shown in the trailing slot after a failed send — a quiet, modern inline
/// card (not a 2010 banner): the user's text stays in its optimistic bubble
/// above, this explains what happened and offers a one-tap retry.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Container(
        key: const Key('error-retry'),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: TrainColors.ember.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TrainColors.ember.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.warning, size: 17, color: TrainColors.ember),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l(context).askUnreachableTitle,
                    style: AppText.rowTitle.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l(context).askUnreachableBody,
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      height: 1.3,
                      color: TrainColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PressableScale(
              child: Material(
                color: TrainColors.violetWash,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    child: Text(
                      l(context).askRetry,
                      style: AppText.button.copyWith(color: TrainColors.violet),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
