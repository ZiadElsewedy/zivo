import 'body_weight_entry.dart';

/// The Workout Dashboard's weight-over-time picture, built from
/// [BodyWeightEntry] logs.
class WeightTrend {
  const WeightTrend({
    required this.latest,
    required this.changeKgOverWindow,
    required this.series,
  });

  /// The most recent entry, or null if nothing's been logged yet.
  final BodyWeightEntry? latest;

  /// [latest] minus the oldest entry still inside the trend window, or null
  /// when there are fewer than two entries in that window to compare.
  final double? changeKgOverWindow;

  /// Every entry inside the window, oldest first — chart-ready.
  final List<BodyWeightEntry> series;
}

/// Computes [WeightTrend] from every logged entry, restricted to the last
/// [window] (default 30 days) ending at [now].
WeightTrend computeWeightTrend({
  required List<BodyWeightEntry> entries,
  required DateTime now,
  Duration window = const Duration(days: 30),
}) {
  final cutoff = now.subtract(window);
  final inWindow = entries.where((e) => !e.loggedAt.isBefore(cutoff)).toList()
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  final latest = entries.isEmpty
      ? null
      : entries.reduce((a, b) => a.loggedAt.isAfter(b.loggedAt) ? a : b);

  final change = inWindow.length < 2 ? null : inWindow.last.weightKg - inWindow.first.weightKg;

  return WeightTrend(latest: latest, changeKgOverWindow: change, series: inWindow);
}
