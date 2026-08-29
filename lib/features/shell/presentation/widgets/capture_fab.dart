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
        // Presence without a hue. The audit's note was fair — a muted disc on
        // a black ground barely reads — but the fix can't be an ember fill:
        // Today's ember belongs to Start Workout (see the class doc), and
        // "one hue = one meaning" makes ember the single committing action.
        // So it borrows the chrome's own material instead — the same raised
        // fill, top-lit gradient and hairline the nav island a few pixels
        // below it wears — which is what lifts it off the ground here.
        //
        // The ramp is baked into opaque stops rather than layering
        // `cardGradient` over a `color`: in a BoxDecoration a gradient
        // installs a *shader*, which overrides `color` outright — the two
        // together would have painted only the 5%-white overlay and left the
        // disc more transparent than before, not less.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF292A29), Color(0xFF212221)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: TrainColors.hairlineStrong),
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
