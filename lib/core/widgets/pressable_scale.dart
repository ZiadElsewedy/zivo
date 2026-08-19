import 'package:flutter/widgets.dart';

import '../motion/springs.dart';

/// Instant, physical press feedback for any tappable widget — scales [child]
/// down on the very first pointer-down frame (never waiting for a completed
/// tap) and springs back on release/cancel.
///
/// Purely visual: it listens to raw pointer events rather than competing in
/// the gesture arena, so it never intercepts or double-fires the tap itself
/// — drop it around a button that already owns its own `onTap` (a
/// `PillButton`, an `InkWell`) with zero risk of double-invoking it.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.scale = 0.97, this.enabled = true});

  final Widget child;

  /// The scale factor at full press. Small and critically damped — this is
  /// feedback, not a bounce.
  final double scale;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, value: 1);

  void _animateTo(double target) {
    if (reducedMotion(context)) {
      _controller.value = target;
      return;
    }
    _controller.springTo(target, spring: AppSprings.press);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _animateTo(widget.scale) : null,
      onPointerUp: widget.enabled ? (_) => _animateTo(1) : null,
      onPointerCancel: widget.enabled ? (_) => _animateTo(1) : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
