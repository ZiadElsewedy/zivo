import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/train_tokens.dart';

/// A full-width pill action button for the auth flow, matching ZIVO's
/// [PillButton] proportions but supporting a leading [icon] widget, a busy
/// [loading] spinner, and an optional outline (for the light Google/Apple
/// buttons).
///
/// **Enabled it is lit; disabled it recedes.** Previously a disabled button
/// kept its bright fill and only dropped to 50% opacity — which on a dark
/// screen left a pale slab as the single brightest thing in view, drawing the
/// eye to the one control that could not be used (the Verify screen was the
/// worst case). Now an unavailable action falls back to a recessed
/// surface with tertiary ink: still visibly present and clearly next, but no
/// longer outranking the content that has to be filled in to earn it. An
/// available primary action gets the reverse treatment — a soft vertical
/// gradient and the ember glow — so "ready" is something you can see across
/// the room.
///
/// Motion: the label cross-fades into the spinner (no abrupt swap), the fill
/// eases between states, and the whole pill presses down physically on touch
/// via [PressableScale].
class AuthActionButton extends StatelessWidget {
  const AuthActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.background = TrainColors.ember,
    this.foreground = TrainColors.base,
    this.border,
    this.loading = false,
    this.enabled = true,
    super.key,
  });

  final String label;

  /// Optional leading mark (Apple logo, Google "G", a forward arrow).
  /// Uncoloured icons inherit the button's resolved foreground; the brand
  /// marks keep their own colours. Omitted, the label centres exactly — an
  /// empty placeholder widget still drags it off-centre by the gap's width.
  final Widget? icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color? border;
  final bool loading;
  final bool enabled;

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    // A disabled action still shows its shape and label, just recessed — it is
    // the next step, not a dead control.
    final fill = enabled ? background : TrainColors.raisedStrong;
    final ink = enabled ? foreground : TrainColors.ink3;
    final lit = enabled && background == TrainColors.ember;

    final radius = BorderRadius.circular(AppRadius.pill);

    return Opacity(
      // Light, not heavy: the recessed fill and tertiary ink already carry
      // "not yet". Stacking the old 50% wash on top of them washed the label
      // out to the point the button stopped reading as a control at all.
      opacity: enabled ? 1 : 0.82,
      child: PressableScale(
        enabled: active,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: AppMotion.ease,
          height: _height,
          decoration: BoxDecoration(
            color: lit ? null : fill,
            // A barely-there vertical lift on the primary action: the top edge
            // catches the light, the bottom sits in it.
            gradient: lit
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF6E33), TrainColors.ember],
                  )
                : null,
            borderRadius: radius,
            border: enabled && border != null
                ? Border.all(color: border!, width: 1.4)
                : null,
            boxShadow: lit
                ? const [
                    BoxShadow(
                      color: Color(0x38FF5A1F),
                      blurRadius: 28,
                      spreadRadius: -10,
                      offset: Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: active ? onTap : null,
              borderRadius: radius,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.92,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  // Layout must not jump between states — both children are
                  // centred in the same fixed-height box.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.center,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: loading
                      ? SizedBox(
                          key: const ValueKey('busy'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ink,
                          ),
                        )
                      : IconTheme(
                          key: const ValueKey('idle'),
                          data: IconThemeData(color: ink, size: 18),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                icon!,
                                const SizedBox(width: 10),
                              ],
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 260),
                                curve: AppMotion.ease,
                                style: AppText.button.copyWith(
                                  fontSize: 16,
                                  letterSpacing: 0.1,
                                  color: ink,
                                ),
                                child: Text(label),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
