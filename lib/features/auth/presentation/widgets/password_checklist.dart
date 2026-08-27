import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/password_policy.dart';

/// Live per-rule feedback for [PasswordPolicy], rendered under a password field
/// so the user knows exactly what's missing. Each rule's tint eases between
/// met/unmet rather than snapping. Shared by sign-up, password reset, and
/// change-password so the requirement UI is identical everywhere.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in PasswordPolicy.rules)
          _ChecklistRow(
            label: rule.label,
            met: rule.isSatisfiedBy(password),
          ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: AppColors.ink3, end: met ? AppColors.pulseText : AppColors.ink3),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, color, child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              met ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(label, style: AppText.meta.copyWith(color: color)),
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
