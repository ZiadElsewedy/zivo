/// Formatting shared across the whole workout feature.
///
/// `trimWeight` existed twice — once as `trimWeight` in the live session's
/// format module and once as a file-private `_trimWeight` at the top of the
/// plan editor — with identical bodies. How ZIVO writes a weight is a product
/// decision, and two copies is one too many for a decision to live in.
library;

import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';

/// "60" / "22.5" — a weight without a trailing ".0".
String trimWeight(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "52m" under an hour, "1h 12m" past one.
///
/// This lived on `workout_dashboard_page.dart` and was *also* copied verbatim
/// into `workout_stats_pages.dart` as a file-private `_durationLabel` — three
/// pages imported a page to borrow it. How ZIVO writes a duration is a product
/// decision, same as `trimWeight` above, so it belongs here; and the `h`/`m`
/// abbreviations are copy, so they come from the `.arb` rather than the source.
String formatDurationShort(BuildContext context, Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return l(context).workoutDurationHm(hours, minutes);
  return l(context).workoutDurationM(minutes);
}
