import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/readiness.dart';
import '../readiness_labels.dart';
import '../widgets/readiness_glance.dart';

/// The readiness detail page: the call, every factor with the number behind it,
/// how it was worked out (and what it is not), and an optional route into the
/// coach to talk it over. Reached from the Today card.
class ReadinessPage extends StatelessWidget {
  const ReadinessPage({required this.readiness, this.onOpenAsk, super.key});

  final Readiness readiness;

  /// Switches to the Ask tab. When null the "Ask ZIVO about this" button is
  /// hidden (e.g. the page opened outside the shell, or in a test).
  final VoidCallback? onOpenAsk;

  @override
  Widget build(BuildContext context) {
    final verdict = readinessVerdictCopy(context, readiness.verdict);
    final bottom = TrainBottomInset.of(context);

    return TrainScreen(
      tint: TrainColors.hubTint,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.m,
          AppSpacing.screen,
          bottom,
        ),
        children: [
          TrainPageHeader(title: l(context).readinessDetailTitle),
          const SizedBox(height: AppSpacing.l),
          _VerdictCard(verdict: verdict),
          const SizedBox(height: AppSpacing.l),
          if (readiness.factors.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                gradient: TrainColors.cardGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TrainColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < readiness.factors.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: TrainColors.hairline),
                      const SizedBox(height: 12),
                    ],
                    ReadinessFactorRow(factor: readiness.factors[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
          ],
          _HowCard(),
          if (onOpenAsk != null) ...[
            const SizedBox(height: AppSpacing.l),
            _AskButton(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).maybePop();
                onOpenAsk!();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict});

  final ReadinessVerdictCopy verdict;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: verdict.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: verdict.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(AppIcons.readiness, size: 25, color: verdict.color),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.word,
                  style: TrainType.ui(
                    size: 26,
                    weight: FontWeight.w800,
                    tracking: -0.025,
                    color: verdict.color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  verdict.blurb,
                  style: AppText.body.copyWith(
                    fontSize: 13.5,
                    height: 1.3,
                    color: TrainColors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.info, size: 15, color: TrainColors.ink3),
              const SizedBox(width: AppSpacing.s),
              Text(
                l(context).readinessHowTitle,
                style: AppText.rowTitle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: TrainColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            l(context).readinessHowBody,
            style: AppText.body.copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: TrainColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: TrainColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.chip * 2),
            border: Border.all(color: TrainColors.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.ask, size: 16, color: TrainColors.ink),
              const SizedBox(width: AppSpacing.s),
              Text(
                l(context).readinessAsk,
                style: AppText.rowTitle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TrainColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
