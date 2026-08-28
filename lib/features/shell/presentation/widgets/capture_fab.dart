import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';

/// The global Quick Capture entry, reachable from Today.
///
/// Deliberately NOT ember any more: Today's ember belongs to Start Workout,
/// the one committing action on that screen (see the workout-tracking
/// handoff). Two ember discs — one of them floating over the other — read as
/// two equally-primary actions, which is exactly what the rule exists to
/// prevent. A frosted glass disc keeps capture one tap away without claiming
/// the screen's accent.
class CaptureFab extends StatelessWidget {
  const CaptureFab({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF20211F),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            spreadRadius: -6,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const Icon(
            AppIcons.add,
            color: TrainColors.inkPlain,
            size: 26,
          ),
        ),
      ),
    );
  }
}
