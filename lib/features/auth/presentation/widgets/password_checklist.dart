import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/password_policy.dart';

/// Live feedback on how far a password has got through [PasswordPolicy] —
/// a strength bar with a named level, and the individual rules as chips that
/// light as they're met.
///
/// This replaces a four-line vertical checklist, which had two problems: it
/// was taller than the field it described (so it read as loose page content
/// floating between two inputs rather than as *that field's* feedback), and
/// four unchecked circles is the least encouraging way to greet someone who
/// has typed nothing. A bar reads as progress at a glance and the chips wrap
/// to two short rows, so the panel is roughly half the height and clearly
/// belongs to the password above it.
///
/// Every chip keeps the rule's full sentence as its semantic label, so the
/// compact form costs nothing to a screen reader.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    final rules = PasswordPolicy.rules;
    final met = PasswordPolicy.metCount(password);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _StrengthBar(met: met, total: rules.length)),
              const SizedBox(width: 12),
              _StrengthLabel(met: met, total: rules.length),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final rule in rules)
                _RuleChip(rule: rule, met: rule.isSatisfiedBy(password)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tint a given amount of policy progress earns. Deliberately the app's
/// existing hues rather than a new traffic-light ramp: flare already means
/// "not there yet", solar "partway", pulse "good".
Color _strengthTint(int met, int total) {
  if (met == 0) return AppColors.ink3;
  if (met >= total) return AppColors.pulseText;
  return met <= total / 2 ? AppColors.flareText : AppColors.solarText;
}

/// A segmented meter — one segment per rule, filling left to right. Segments
/// rather than a continuous bar because the policy is discrete: four things
/// are either done or not, and four blocks say how many are left without the
/// user counting chips.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.met, required this.total});

  final int met;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tint = _strengthTint(met, total);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: AppMotion.ease,
              height: 4,
              decoration: BoxDecoration(
                color: i < met ? tint : AppColors.hairline2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StrengthLabel extends StatelessWidget {
  const _StrengthLabel({required this.met, required this.total});

  final int met;
  final int total;

  String get _text {
    if (met == 0) return 'Password strength';
    if (met >= total) return 'Strong';
    return met <= total / 2 ? 'Weak' : 'Almost';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _strengthTint(met, total)),
      duration: const Duration(milliseconds: 260),
      curve: AppMotion.ease,
      builder: (context, color, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: Text(
          _text,
          key: ValueKey(_text),
          style: AppText.sectionLabel.copyWith(
            fontSize: 10.5,
            letterSpacing: 0.9,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// One requirement, as a pill that fills when it's satisfied. The tint eases
/// rather than snapping so a rule being met registers as a small event.
class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.rule, required this.met});

  final PasswordRule rule;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${rule.label}: ${met ? 'met' : 'not met'}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: AppMotion.ease,
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: met ? AppColors.pulseWash : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: met
                ? AppColors.pulse.withValues(alpha: 0.32)
                : AppColors.hairline2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: AppMotion.ease,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.5, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                met ? Icons.check_rounded : Icons.circle_outlined,
                key: ValueKey(met),
                size: 13,
                color: met ? AppColors.pulseText : AppColors.ink3,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              rule.shortLabel,
              style: AppText.meta.copyWith(
                fontSize: 12,
                color: met ? AppColors.pulseText : AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline feedback on whether a confirm-password field matches the first
/// password. Its tint eases between the match/mismatch colors rather than
/// snapping; the caller controls when it is [visible].
class PasswordMatchHint extends StatelessWidget {
  const PasswordMatchHint({
    required this.matches,
    required this.visible,
    super.key,
  });

  final bool matches;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        begin: AppColors.flareText,
        end: matches ? AppColors.pulseText : AppColors.flareText,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, color, _) {
        final icon = matches
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded;
        final label = matches ? 'Passwords match' : "Passwords don't match";
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(label, style: AppText.meta.copyWith(color: color)),
            ],
          ),
        );
      },
    );
  }
}
