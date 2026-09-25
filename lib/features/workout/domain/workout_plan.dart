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

  /// The next WORKOUT due: the day whose `order` matches [cycleCursor], or —
  /// when that slot is a rest day — the first workout after it in the
  /// rotation. Null only when the plan has no workout days at all.
  ///
  /// Never a rest day. Every caller of this starts, swaps or describes a
  /// session, and a rest slot is none of those; whether TODAY is a rest day is
  /// a calendar question answered by `training_days.dart`, not by the cursor.
  ///
  /// Defensive fallback to the first day by `order` when no day matches
  /// [cycleCursor] (e.g. a stale cursor from before this invariant was
  /// enforced) — a plan with days should never read as "nothing up next."
  WorkoutDay? get nextDay {
    final sorted = sortedDays;
    if (sorted.isEmpty) return null;
    var start = sorted.indexWhere((d) => d.order == cycleCursor);
    if (start < 0) start = 0;
    for (var i = 0; i < sorted.length; i++) {
      final day = sorted[(start + i) % sorted.length];
      if (day.isWorkout) return day;
    }
    return null;
  }

  /// [days] in rotation order.
  List<WorkoutDay> get sortedDays =>
      [...days]..sort((a, b) => a.order.compareTo(b.order));

  /// The days that are workouts, in rotation order.
  List<WorkoutDay> get workoutDays => [
    for (final d in sortedDays)
      if (d.isWorkout) d,
  ];

  /// Whether the cycle spells out its rest days. Only then is a day with
  /// nothing logged a *missed* workout — a pure rotation (Push → Pull → Legs)
  /// leaves rest implicit, and treating every unlogged day as missed would call
  /// the rest the plan assumes an error.
  bool get schedulesRest => days.any((d) => d.isRest);

  /// How many rest days immediately follow [dayId] in the rotation (wrapping,
  /// stopping at the next workout). 0 for an unknown id or a pure rotation.
  int restDaysAfter(String dayId) {
    final sorted = sortedDays;
    final index = sorted.indexWhere((d) => d.id == dayId);
    if (index < 0) return 0;
    var count = 0;
    for (var i = 1; i < sorted.length; i++) {
      if (!sorted[(index + i) % sorted.length].isRest) break;
      count++;
    }
    return count;
  }

  /// The first workout after [dayId] in the rotation (wrapping; may be the day
  /// itself in a one-workout cycle). Null when [dayId] is unknown or the plan
  /// has no workouts.
  WorkoutDay? workoutAfter(String dayId) {
    final sorted = sortedDays;
    final index = sorted.indexWhere((d) => d.id == dayId);
    if (index < 0) return null;
    for (var i = 1; i <= sorted.length; i++) {
      final day = sorted[(index + i) % sorted.length];
      if (day.isWorkout) return day;
    }
    return null;
  }

  /// A copy with [cycleCursor] advanced to the next day in the rotation,
  /// wrapping back to the first once past the last. Pure — does not mutate
  /// this instance.
  WorkoutPlan advanceCursor() {
    if (days.isEmpty) return this;
    // Landing on a rest slot is fine: [nextDay] reads past it.
    return copyWith(cycleCursor: (cycleCursor + 1) % days.length);
  }

  /// A copy with the cursor moved to whichever day FOLLOWS [dayId] in the
  /// rotation (wrapping past the last). This is how completion should always
  /// advance the cycle now that any day can be trained in any order: finishing
  /// "Pull" out of sequence must move the recommendation PAST Pull — the old
  /// blind `+1` from wherever the cursor happened to be could desync the
  /// recommendation from what was actually trained.
  ///
  /// A [dayId] that no longer exists (the plan was edited mid-session) falls
  /// back to the blind one-step advance rather than corrupting the cursor.
  WorkoutPlan advanceToAfterDay(String dayId) {
    if (days.isEmpty) return this;
    final sorted = sortedDays;
    final index = sorted.indexWhere((d) => d.id == dayId);
    if (index < 0) return advanceCursor();
    return copyWith(cycleCursor: sorted[(index + 1) % sorted.length].order);
  }

  /// A copy with [aId] and [bId] trading places in the rotation — each takes
  /// the other's `order`. The cursor is deliberately **not** moved: it stores
  /// an `order`, so it keeps pointing at the same POSITION in the cycle, which
  /// now holds the other day.
  ///
  /// This is the "train something else today without losing what was due"
  /// rule. Starting an out-of-rotation day on its own drops the due day from
  /// the cycle, because [advanceToAfterDay] moves the recommendation PAST what
  /// was trained; swapping the two first means every day still comes up
  /// exactly once, so a week meant to cover the whole body still does.
  ///
  /// `slot` stays with its day — it is the day's identity ("Day B is Arms"),
  /// not its position, which is why reordering in the editor doesn't reassign
  /// it either. Returns `this` when the two ids are the same or either one is
  /// not in [days], and when either is a rest day — rest is a place in the
  /// calendar, not a workout to trade (a swap onto a rest slot would make the
  /// due workout itself vanish into the rest position).
  WorkoutPlan swapDays(String aId, String bId) {
    if (aId == bId) return this;
    WorkoutDay? a;
    WorkoutDay? b;
    for (final day in days) {
      if (day.id == aId) a = day;
      if (day.id == bId) b = day;
    }
    if (a == null || b == null) return this;
    if (a.isRest || b.isRest) return this;
    final aOrder = a.order;
    final bOrder = b.order;
    return copyWith(
      days: [
        for (final day in days)
          if (day.id == aId)
            day.copyWith(order: bOrder)
          else if (day.id == bId)
            day.copyWith(order: aOrder)
          else
            day,
      ],
    );
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
