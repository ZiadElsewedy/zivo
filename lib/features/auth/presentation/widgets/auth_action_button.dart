import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';

/// A full-width pill action button for the auth screen, matching ZIVO's
/// [PillButton] proportions but supporting a leading [icon] widget, a busy
/// [loading] spinner, and an optional outline (for the light Google/Apple
/// buttons).
///
/// Motion: the label cross-fades into the spinner (no abrupt swap), and the
/// whole pill presses down physically on touch via [PressableScale].
class AuthActionButton extends StatelessWidget {
  const AuthActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.background = AppColors.ink,
    this.foreground = AppColors.ground,
    this.border,
    this.loading = false,
    this.enabled = true,
    super.key,
  });

  final String label;

  /// Leading mark (Apple logo, Google "G", etc.).
  final Widget icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color? border;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        enabled: active,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            onTap: active ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: border == null
                  ? null
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: border!, width: 1.4),
                    ),
              alignment: Alignment.center,
              height: 54,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                // Layout must not jump between states — both children are
                // centred in the same fixed-height box.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    ?currentChild,
                  ],
                ),
                child: loading
                    ? SizedBox(
                        key: const ValueKey('busy'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Row(
                        key: const ValueKey('idle'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Text(
                            label,
                            style: AppText.button
                                .copyWith(fontSize: 16, color: foreground),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
