import 'package:flutter/material.dart';

/// App-wide scroll feel: iOS-style momentum + rubber-band overscroll on every
/// platform, and no Material overscroll glow. Applied via
/// `MaterialApp.scrollBehavior` so every list, grid, and sheet shares the same
/// fluid, Apple-like scrolling.
///
/// **Don't pass `physics:` to a scroll view to get this feel — it is already
/// inherited.** Restating it drifts: a bare `BouncingScrollPhysics()` drops
/// the [AlwaysScrollableScrollPhysics] parent below, so that one screen
/// stopped bouncing whenever its content happened to fit the viewport while
/// every other screen still did. The music player, the plan editor and two of
/// the live session's lists had each grown their own copy, and no two of them
/// agreed.
///
/// The one legitimate override is [NeverScrollableScrollPhysics] on a nested,
/// shrink-wrapped list or grid that must not scroll on its own (the Hub's
/// module grid, the plan editor's inner day list) — that is a different
/// statement, not a different feel.
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
  ) => child; // The bounce itself is the feedback — no glow.
}
