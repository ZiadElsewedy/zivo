import 'package:flutter/widgets.dart';

import 'zivo_bottom_bar.dart';

/// The measured height of the shell's bottom chrome — the floating nav island
/// plus, when music is on screen, the now-playing strip fused to its top edge
/// — published to every page beneath it.
///
/// The bottom of the screen is **one object**, not a stack of independent
/// floating layers, and this is the number that makes that true in code.
/// Before it, each surface guessed its own clearance and the guesses had
/// already drifted apart: Today reserved a magic `86` for music, You reserved
/// a different `86`, and the Hub reserved nothing at all — so Hub content sat
/// under the strip, and the capture FAB rode up over Today's "Start Workout"
/// whenever a track started. Deriving every offset from one value means those
/// collisions can't come back: a page cannot be out of date about a height it
/// doesn't own, and it re-lays-out automatically when music appears or leaves.
///
/// Read it with [BottomChrome.of]; the shell provides it in `home_shell.dart`.
class BottomChrome extends InheritedWidget {
  const BottomChrome({required this.height, required super.child, super.key});

  /// Total rendered footprint measured up from the bottom of the screen,
  /// safe-area inset included. Add a page's own breathing room on top of it.
  final double height;

  /// The chrome height for [context], rebuilding the caller when it changes.
  ///
  /// Falls back to the nav island's own height when there is no chrome above
  /// the caller — a route pushed over the shell, or a page pumped directly in
  /// a widget test — which is exactly what those callers computed before.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BottomChrome>()?.height ??
      ZivoBottomBarMetrics.height(context);

  @override
  bool updateShouldNotify(BottomChrome oldWidget) =>
      oldWidget.height != height;
}
