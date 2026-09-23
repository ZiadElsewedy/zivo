import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_failure.dart';

/// Shown in the trailing slot after a failed send — a quiet, modern inline
/// card (not a 2010 banner): the user's text stays in its optimistic bubble
/// above, this explains what happened and offers a one-tap retry.
///
/// The words follow [failure]: every AI model being down, the daily limit
/// and a timeout each say what they are. None of them names a provider or a
/// bill — that's ZIVO's problem, not the reader's.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    required this.onRetry,
    this.failure = AiFailureKind.network,
    super.key,
  });

  final VoidCallback onRetry;
  final AiFailureKind failure;

  (String, String) _copy(BuildContext context) => switch (failure) {
    AiFailureKind.unavailable => (
      l(context).aiErrorUnavailableTitle,
      l(context).aiErrorUnavailableBody,
    ),
    AiFailureKind.dailyLimit => (
      l(context).aiErrorDailyLimitTitle,
      l(context).aiErrorDailyLimitBody,
    ),
    AiFailureKind.timeout => (
      l(context).aiErrorTimeoutTitle,
      l(context).aiErrorTimeout,
    ),
    AiFailureKind.unknown => (
      l(context).askUnreachableTitle,
      l(context).aiErrorGeneric,
    ),
    _ => (
      l(context).askUnreachableTitle,
      l(context).askUnreachableBody,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (title, body) = _copy(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Container(
        key: const Key('error-retry'),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: TrainColors.ember.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TrainColors.ember.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(AppIcons.warning, size: 17, color: TrainColors.ember),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.rowTitle.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
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
