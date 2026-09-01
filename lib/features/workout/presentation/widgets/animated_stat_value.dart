import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';

/// A stat/label value that fades + slides in whenever it changes (a new
/// week, a streak ticking up, a session's status flipping from "In
/// progress" to "Completed") — keyed on the text itself so any genuinely
/// new value re-triggers, rather than the text (and, where [style] carries
/// a state color, the color) just snapping. Shared by the dashboard and
/// progress pages rather than forked per file.
class AnimatedStatValue extends StatelessWidget {
  const AnimatedStatValue({
    required this.value,
    required this.style,
    super.key,
  });

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - animation.value) * 6),
            child: child,
          ),
          child: child,
        ),
      ),
      child: Text(value, key: ValueKey(value), style: style),
    );
  }
}
