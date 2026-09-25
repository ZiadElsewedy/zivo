import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../../../core/motion/springs.dart';

/// Horizontal swipe between exercises that **follows the finger**.
///
/// The exercise heading slides with the drag and fades a little as it goes,
/// so the gesture shows what it will do before it does it. Past the
/// threshold (distance or a flick) it commits — the page's directional
/// transition takes over from wherever the drag left off. Short of it, the
/// heading springs home.
///
/// With nowhere to go (one exercise left) the drag still answers, but under
/// heavy resistance: a rubber band says "nothing there" better than a
/// gesture that does nothing at all.
class ExerciseSwipe extends StatefulWidget {
  const ExerciseSwipe({
    required this.child,
    required this.onNext,
    required this.onPrevious,
    super.key,
  });

  final Widget child;

  /// Null when there is no other exercise to move to.
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  @override
  State<ExerciseSwipe> createState() => _ExerciseSwipeState();
}

class _ExerciseSwipeState extends State<ExerciseSwipe>
    with SingleTickerProviderStateMixin {
  /// The heading's horizontal offset, in logical pixels.
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  );

  static const _commitDistance = 84.0;
  static const _commitVelocity = 420.0;
  bool _armed = false;

  bool get _canMove => widget.onNext != null && widget.onPrevious != null;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    _dx.stop();
    // Resistance grows with distance; with nowhere to go it is a hard band.
    final resistance = _canMove ? 0.55 : 0.18;
    _dx.value += d.delta.dx * resistance;
    final armed = _canMove && _dx.value.abs() >= _commitDistance * 0.55;
    if (armed != _armed) {
      _armed = armed;
      // One tick as the gesture crosses into "this will commit".
      if (armed) HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final commit =
        _canMove &&
        (_dx.value.abs() >= _commitDistance * 0.55 ||
            v.abs() >= _commitVelocity);
    _armed = false;
    if (commit) {
      final towardStart = (_dx.value.abs() > 1 ? _dx.value : v) < 0;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      // Pulling content toward the reading start brings the next one in,
      // like turning a page.
      (towardStart != rtl ? widget.onNext : widget.onPrevious)!();
      return;
    }
    _springHome(v);
  }

  void _springHome(double velocity) {
    if (reducedMotion(context)) {
      _dx.value = 0;
      return;
    }
    _dx.animateWith(
      SpringSimulation(AppSprings.standard, _dx.value, 0, velocity * 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('exercise-swipe'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => _springHome(0),
      child: AnimatedBuilder(
        animation: _dx,
        builder: (context, child) {
          final t = (_dx.value.abs() / 220).clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - t * 0.45,
            child: Transform.translate(
              offset: Offset(_dx.value, 0),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
