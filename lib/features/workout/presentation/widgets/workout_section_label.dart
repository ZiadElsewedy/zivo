import 'package:flutter/widgets.dart';

import '../../../../core/widgets/train_surfaces.dart';

/// The section caption above each block on the workout drill-down pages —
/// the design handoff's caption: mono, uppercase, wide-tracked, dim. It
/// labels; it never competes (identity §6).
///
/// A thin wrapper over [TrainSectionLabel] rather than a second
/// implementation, so the workout pages and every other handoff surface
/// can't drift apart. Kept as its own name because a dozen call sites in
/// this feature already read `WorkoutSectionLabel('Training')`.
class WorkoutSectionLabel extends StatelessWidget {
  const WorkoutSectionLabel(this.label, {this.trailing, super.key});

  final String label;

  /// An optional right-aligned qualifier ("LAST 7 DAYS", "ALL TIME").
  final String? trailing;

  @override
  Widget build(BuildContext context) =>
      TrainSectionLabel(label, trailing: trailing);
}
