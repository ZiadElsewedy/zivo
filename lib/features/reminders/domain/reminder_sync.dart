import 'package:flutter/foundation.dart';

/// An optional link between a [Reminder] and the user's plans, so a meal or
/// workout reminder can carry more than a bare title.
///
/// `null` on a reminder means a plain reminder — the original behaviour, and the
/// only shape older stored reminders have. A sync is a small, self-describing
/// value persisted as a nested map under the reminder's `sync` key (tagged by
/// `type`, decoded tolerantly like every other stored field).
///
/// Two flavours, matching the two things a reminder can be about:
/// - [MealSync] is a **snapshot** the user shaped once: which plan meal it is
///   and the exact item lines to show in the notification. It never changes on
///   its own — re-open and re-sync to refresh it.
/// - [WorkoutSync] is a **live link**: the notification's text is re-resolved
///   from the active plan's next-up day every time the scheduler reschedules
///   (see `LocalNotificationScheduler` + the app-root wiring). [cachedDayLabel]
///   holds the last resolved day name purely so the reminders list can label the
///   row without recomputing the rotation.
sealed class ReminderSync {
  const ReminderSync();

  Map<String, dynamic> toMap();

  /// Decodes a stored sync, returning null for anything missing or unrecognised
  /// — a reminder must always remain readable, so an unknown sync degrades to a
  /// plain reminder rather than failing to decode.
  static ReminderSync? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'meal' => MealSync.fromMap(raw),
      'workout' => WorkoutSync.fromMap(raw),
      _ => null,
    };
  }
}

/// A meal reminder synced from the diet plan: [mealLabel] is which plan meal it
/// represents ("Lunch"), [items] is the customised set of lines to show in the
/// notification body (the user can have added or removed some).
@immutable
class MealSync extends ReminderSync {
  const MealSync({required this.mealLabel, this.items = const []});

  final String mealLabel;
  final List<String> items;

  @override
  Map<String, dynamic> toMap() => {
    'type': 'meal',
    'mealLabel': mealLabel,
    'items': items,
  };

  static MealSync fromMap(Map raw) => MealSync(
    mealLabel: raw['mealLabel'] is String ? raw['mealLabel'] as String : '',
    items: [
      for (final item in (raw['items'] as List? ?? const []))
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is MealSync &&
      other.mealLabel == mealLabel &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(mealLabel, Object.hashAll(items));
}

/// A workout reminder linked to the active plan. Carries no schedule payload of
/// its own — the title/body are resolved live at reschedule time — beyond
/// [cachedDayLabel], the last known next-up day name, kept only for the list row.
///
/// [motivational] flips the notification from the day's exercise list to a short
/// line of encouragement (see `workout_motivations.dart`): the day is still
/// named, but the body is a rotating motivational phrase rather than the lift
/// details. Off by default, so the original behaviour is unchanged.
@immutable
class WorkoutSync extends ReminderSync {
  const WorkoutSync({this.cachedDayLabel, this.motivational = false});

  final String? cachedDayLabel;
  final bool motivational;

  @override
  Map<String, dynamic> toMap() => {
    'type': 'workout',
    if (cachedDayLabel != null) 'cachedDayLabel': cachedDayLabel,
    if (motivational) 'motivational': true,
  };

  static WorkoutSync fromMap(Map raw) => WorkoutSync(
    cachedDayLabel: raw['cachedDayLabel'] is String
        ? raw['cachedDayLabel'] as String
        : null,
    motivational: raw['motivational'] is bool
        ? raw['motivational'] as bool
        : false,
  );

  @override
  bool operator ==(Object other) =>
      other is WorkoutSync &&
      other.cachedDayLabel == cachedDayLabel &&
      other.motivational == motivational;

  @override
  int get hashCode => Object.hash(cachedDayLabel, motivational);
}
