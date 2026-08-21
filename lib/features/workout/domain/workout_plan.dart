import 'workout_day.dart';
import 'workout_plan_source.dart';
import 'workout_plan_status.dart';

/// The user's workout plan — an ordered rotating cycle of [WorkoutDay]s
/// (Day A -> B -> C -> ... -> A), not tied to weekdays. [cycleCursor] tracks
/// which day's `order` is next up.
class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.days,
    this.cycleCursor = 0,
  });

  final String id;
  final String name;
  final WorkoutPlanStatus status;
  final WorkoutPlanSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkoutDay> days;
  final int cycleCursor;

  /// The day whose `order` matches [cycleCursor]; null only if [days] is
  /// empty. Defensive fallback to the first day by `order` when no day
  /// matches [cycleCursor] (e.g. a stale cursor from before this invariant
  /// was enforced) — a plan with days should never read as "nothing up
  /// next."
  WorkoutDay? get nextDay {
    if (days.isEmpty) return null;
    for (final day in days) {
      if (day.order == cycleCursor) return day;
    }
    final sorted = [...days]..sort((a, b) => a.order.compareTo(b.order));
    return sorted.first;
  }

  /// A copy with [cycleCursor] advanced to the next day in the rotation,
  /// wrapping back to the first once past the last. Pure — does not mutate
  /// this instance.
  WorkoutPlan advanceCursor() {
    if (days.isEmpty) return this;
    return copyWith(cycleCursor: (cycleCursor + 1) % days.length);
  }

  WorkoutPlan copyWith({
    String? name,
    WorkoutPlanStatus? status,
    List<WorkoutDay>? days,
    DateTime? updatedAt,
    int? cycleCursor,
  }) => WorkoutPlan(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    days: days ?? this.days,
    cycleCursor: cycleCursor ?? this.cycleCursor,
  );
}
