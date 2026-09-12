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

/// The readiness detail page: the call first (always), a plain-language note on
/// what Daily Readiness is, every factor with the number behind it, how it was
/// worked out (and what it is not), and an optional route into the coach to talk
/// it over. Reached from the Today card.
///
/// Order is deliberate: the **call is the hero and stays first** — it is the
/// day's value — then "what is this", then "why this call" (the factors), then
/// "how it's worked out". Newcomer or regular, the recommendation is the first
/// thing the eye lands on.
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
          // The call — always first, dressed as the hero of the page.
          _VerdictCard(verdict: verdict),
          const SizedBox(height: AppSpacing.m),
          // What the feature is, in plain language, for anyone meeting it new.
          _AboutCard(),
          if (readiness.factors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.l),
            _Overline(l(context).readinessWhyCall),
            const SizedBox(height: 10),
            _FactorsCard(factors: readiness.factors),
          ],
          const SizedBox(height: AppSpacing.l),
          _HowCard(),
          if (onOpenAsk != null) ...[
            const SizedBox(height: AppSpacing.m),
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

/// A small uppercase caption used to title a group — the same quiet voice the
/// Today section headers speak in, so the detail page reads as one system.
class _Overline extends StatelessWidget {
  const _Overline(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TrainType.caption(
        size: 9.5,
        tracking: 0.2,
        color: TrainColors.inkAt(0.3),
      ),
    );
  }
}

/// The call itself — the hero. The verdict's status colour is materialised
/// behind it (a soft corner wash + a matching border and low shadow) so the
/// recommendation reads as the one thing on the page, without a new hue.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict});

  final ReadinessVerdictCopy verdict;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: verdict.color.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: verdict.color.withValues(alpha: 0.13),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: TrainColors.cardGradient),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.95),
                    radius: 1.35,
                    colors: [
                      verdict.color.withValues(alpha: 0.16),
                      verdict.color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: verdict.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      AppIcons.readiness,
                      size: 27,
                      color: verdict.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verdict.word,
                          style: TrainType.ui(
                            size: 27,
                            weight: FontWeight.w800,
                            tracking: -0.03,
                            color: verdict.color,
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          verdict.blurb,
                          style: AppText.body.copyWith(
                            fontSize: 14,
                            height: 1.32,
                            color: TrainColors.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "What is Daily Readiness" — the feature in plain language. Carries a light
/// green accent (the coach's supporting voice) so it reads distinctly from the
/// neutral "how it's worked out" note below, and the two never stack as two
/// identical glass surfaces.
class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      decoration: BoxDecoration(
        color: TrainColors.greenWash,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.green.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.ask, size: 15, color: TrainColors.green),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  l(context).readinessAboutTitle,
                  style: AppText.rowTitle.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: TrainColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            l(context).readinessAboutBody,
            style: AppText.body.copyWith(
              fontSize: 12.5,
              height: 1.45,
              color: TrainColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The factors — each with the number it cites — in one card under the
/// "why this call" label.
class _FactorsCard extends StatelessWidget {
  const _FactorsCard({required this.factors});

  final List<ReadinessFactor> factors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < factors.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: TrainColors.hairline),
              const SizedBox(height: 12),
            ],
            ReadinessFactorRow(factor: factors[i]),
          ],
        ],
      ),
    );
  }
}

/// How the call is computed, and — just as important — what it is not. The
/// neutral, secondary reference note; the lighter glass keeps it below the
/// green "about" card in the hierarchy.
class _HowCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      decoration: BoxDecoration(
        color: TrainColors.glassSoft,
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
              Expanded(
                child: Text(
                  l(context).readinessHowTitle,
                  style: AppText.rowTitle.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: TrainColors.ink,
                  ),
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
