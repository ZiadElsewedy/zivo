/// One logged bodyweight reading — a manual "weigh-in", independent of any
/// single workout session, so progress can be tracked over time regardless
/// of training frequency.
class BodyWeightEntry {
  const BodyWeightEntry({
    required this.id,
    required this.weightKg,
    required this.loggedAt,
  });

  final String id;
  final double weightKg;
  final DateTime loggedAt;
}
