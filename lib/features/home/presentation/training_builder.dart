import '../../workout/domain/workout.dart';

/// The most-recently-performed [Workout] logged on [now]'s calendar day, or
/// null if none was.
Workout? todaysWorkout(List<Workout> all, DateTime now) {
  final today = all.where(
    (w) =>
        w.performedAt.year == now.year &&
        w.performedAt.month == now.month &&
        w.performedAt.day == now.day,
  ).toList()..sort((a, b) => b.performedAt.compareTo(a.performedAt));
  return today.isEmpty ? null : today.first;
}
