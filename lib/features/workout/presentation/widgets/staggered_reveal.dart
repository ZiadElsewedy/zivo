import 'dart:async';

import 'package:flutter/material.dart';

/// Fades and slides [child] up into place once, delayed by [index] steps of
/// 40ms — gives a list a premium, cascading reveal the first time it appears
/// (a plain `ListView` otherwise pops in all at once).
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A cancelable Timer (not Future.delayed) — an AnimatedSwitcher phase
    // change can dispose this widget mid-stagger, and an uncancelled delayed
    // callback left pending trips Flutter test's timersPending invariant.
    _timer = Timer(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
