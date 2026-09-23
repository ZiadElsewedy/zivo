import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_failure.dart';
import '../../ai_labels.dart';

/// Shown in the trailing slot after a failed send — a quiet, modern inline
/// card (not a 2010 banner): the user's text stays in its bubble above, this
/// says what went wrong and offers a one-tap retry.
///
/// The words follow [failure]: when the AI provider is what failed, it's
/// named — "Claude isn't available · its usage limit has been reached" —
/// rather than blaming the connection or the message. When switching the
/// active model would fix it, [onSwitchModel] adds a "Switch model" action.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    required this.onRetry,
    this.failure = const AiFailure(AiFailureKind.network),
    this.onSwitchModel,
    super.key,
  });

  final VoidCallback onRetry;
  final AiFailure failure;
  final VoidCallback? onSwitchModel;

  @override
  Widget build(BuildContext context) {
    final title = aiFailureTitle(context, failure);
    final body = aiFailureBody(context, failure);
    final showSwitch =
        onSwitchModel != null && aiFailureSuggestsSwitch(failure);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Container(
        key: const Key('error-retry'),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: TrainColors.ember.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TrainColors.ember.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    AppIcons.warning,
                    size: 17,
                    color: TrainColors.ember,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const Key('error-retry-title'),
                        style: AppText.rowTitle.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: TrainColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        key: const Key('error-retry-body'),
                        style: AppText.body.copyWith(
                          fontSize: 13,
                          height: 1.35,
                          color: TrainColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showSwitch) ...[
                  _Action(
                    key: const Key('error-switch-model'),
                    label: l(context).aiSwitchModel,
                    onTap: onSwitchModel!,
                    filled: false,
                  ),
                  const SizedBox(width: 8),
                ],
                _Action(
                  key: const Key('error-retry-button'),
                  label: l(context).askRetry,
                  onTap: onRetry,
                  filled: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    required this.filled,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: filled ? TrainColors.violetWash : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: TrainColors.hairlineStrong),
                  ),
            child: Text(
              label,
              style: AppText.button.copyWith(
                color: filled ? TrainColors.violet : TrainColors.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
