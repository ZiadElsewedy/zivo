import 'package:flutter/material.dart';

/// App-wide scroll feel: iOS-style momentum + rubber-band overscroll on every
/// platform, and no Material overscroll glow. Applied via
/// `MaterialApp.scrollBehavior` so every list, grid, and sheet shares the same
/// fluid, Apple-like scrolling.
class ZivoScrollBehavior extends MaterialScrollBehavior {
  const ZivoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // The bounce itself is the feedback — no glow.
}
