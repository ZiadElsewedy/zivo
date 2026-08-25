import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Entrance motion in the ZIVO identity: content rises into place along the
/// 8° lean (up and slightly to the right), brisk then still. Staggered by
/// [delay]. Honors the platform "reduce motion" setting.
class RiseIn extends StatefulWidget {
  const RiseIn({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.enter,
  );

  /// A cancelable Timer, not a bare `Future.delayed` — a page can dispose this
  /// widget before the stagger delay elapses (a fast back-swipe, or any test
  /// that pumps one frame and tears down), and an uncancelled delayed callback
  /// left pending trips Flutter test's timersPending invariant.
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.ease);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-9 * (1 - t), 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
