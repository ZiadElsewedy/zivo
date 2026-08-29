import 'package:flutter/material.dart';
import '../../../../core/theme/train_tokens.dart';

/// The bottom-anchored home for an auth screen's primary action.
///
/// Two things this fixes over letting the CTA sit inline at the end of the
/// form. It puts the commit action in one fixed, reachable place on every
/// screen in the flow instead of wherever the content happens to end — which
/// on the short screens left a large dead field of black under a
/// mid-screen button. And because the scrolling content passes *behind* it,
/// the bar needs a scroll edge: a short fade to the ground rather than a hard
/// 1px rule, so text dissolves under the action instead of being chopped by a
/// line.
///
/// The bar rides above the keyboard on its own (the scaffold's inset resize
/// shrinks the body), which is exactly what a form's commit button should do.
class AuthFooterBar extends StatelessWidget {
  const AuthFooterBar({required this.child, this.secondary, super.key});

  /// The primary action.
  final Widget child;

  /// An optional quieter line below it (a resend prompt, a mode switch).
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scroll edge: content fades out into the bar rather than hitting a
        // divider. Only ever drawn where floating chrome overlaps content.
        IgnorePointer(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  TrainColors.base.withValues(alpha: 0),
                  TrainColors.base,
                ],
              ),
            ),
          ),
        ),
        ColoredBox(
          color: TrainColors.base,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child,
                if (secondary != null) ...[
                  const SizedBox(height: 12),
                  secondary!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
