import 'package:flutter/foundation.dart';

import 'reminder_sync.dart';

/// What a reminder is about — general, a meal, or a workout. This decides the
/// row's default icon, the fallback label for a reminder the user never renamed,
/// and which sync affordance the edit sheet offers. It is persisted to Firestore
/// **by `name`**, so it is an id and carries no copy: its labels live in
/// `presentation/reminder_labels.dart` (the same domain-enum-no-copy rule
/// `diet_labels.dart` and `workout_labels.dart` follow).
enum ReminderKind {
  general,
  meal,
  workout;

  /// Decodes a stored kind, falling back to [general] for anything missing or
  /// unrecognised — a value written by a newer build must never leave an old one
  /// unable to read its own reminders. The legacy `"other"` kind has no match
  /// here and so folds into [general], which replaced it.
  static ReminderKind fromName(Object? raw) {
    for (final kind in ReminderKind.values) {
      if (kind.name == raw) return kind;
    }
    return ReminderKind.general;
  }
}

/// A single local reminder: fire a notification at [hour]:[minute] on the
/// chosen [weekdays], carrying [label].
///
/// One flat model covers meals, workouts and "other" — the simplest thing that
/// does the job (see ADR-013). [weekdays] uses Dart's own weekday numbers
/// (`DateTime.monday` = 1 … `DateTime.sunday` = 7); an **empty** set means
/// *every day*, which is both the sensible default and the cheapest to schedule.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.label,
    required this.kind,
    required this.hour,
    required this.minute,
    this.weekdays = const {},
    this.enabled = true,
    this.sync,
    this.emoji,
  });

  /// A stable id, minted once when the reminder is created. Used as the seed
  /// for the OS notification ids so a reschedule replaces rather than duplicates
  /// (see `LocalNotificationScheduler`).
  final String id;

  /// What the user typed. May be empty — the UI shows the kind's label instead.
  final String label;

  final ReminderKind kind;

  /// Wall-clock time, clamped to a real time of day on construction via
  /// [Reminder.clamped].
  final int hour;
  final int minute;

  /// Empty = every day. Otherwise a subset of `DateTime.monday..sunday`.
  final Set<int> weekdays;

  final bool enabled;

  /// An optional link to the user's plans (see [ReminderSync]). `null` is a plain
  /// reminder — the original shape, and what older stored reminders carry.
  final ReminderSync? sync;

  /// An optional emoji the user picked for this reminder — shown on the list row
  /// and prefixed to the notification title so a glance says which reminder it
  /// is. `null` (the default, and what older stored reminders carry) leaves the
  /// kind's icon in place.
  final String? emoji;

  /// True when this reminder fires every day — an empty [weekdays] set, or one
  /// that happens to hold all seven.
  bool get isEveryDay => weekdays.isEmpty || weekdays.length == 7;

  /// The weekdays this reminder actually fires on, always as the full 1..7 set
  /// when [isEveryDay]. The scheduler and the UI both want the concrete days.
  Set<int> get effectiveWeekdays =>
      isEveryDay ? const {1, 2, 3, 4, 5, 6, 7} : weekdays;

  Reminder copyWith({
    String? label,
    ReminderKind? kind,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
    ReminderSync? sync,
    bool clearSync = false,
    String? emoji,
    bool clearEmoji = false,
  }) => Reminder.clamped(
    id: id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    enabled: enabled ?? this.enabled,
    sync: clearSync ? null : (sync ?? this.sync),
    emoji: clearEmoji ? null : (emoji ?? this.emoji),
  );

  /// Builds a reminder with [hour]/[minute]/[weekdays] forced into range, so a
  /// typo or a bad stored value can never produce an unschedulable time.
  factory Reminder.clamped({
    required String id,
    required String label,
    required ReminderKind kind,
    required int hour,
    required int minute,
    Set<int> weekdays = const {},
    bool enabled = true,
    ReminderSync? sync,
    String? emoji,
  }) => Reminder(
    id: id,
    label: label.trim(),
    kind: kind,
    hour: hour.clamp(0, 23),
    minute: minute.clamp(0, 59),
    weekdays: {
      for (final d in weekdays)
        if (d >= DateTime.monday && d <= DateTime.sunday) d,
    },
    enabled: enabled,
    sync: sync,
    // Normalise "" to null so an empty pick never renders as a blank prefix.
    emoji: (emoji != null && emoji.trim().isNotEmpty) ? emoji.trim() : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'hour': hour,
    'minute': minute,
    // Sorted so the stored form is stable regardless of set iteration order —
    // makes round-trip equality and diffing predictable.
    'weekdays': (weekdays.toList()..sort()),
    'enabled': enabled,
    if (sync != null) 'sync': sync!.toMap(),
    if (emoji != null) 'emoji': emoji,
  };

  /// Decodes a stored reminder, tolerant of missing or malformed fields (like
  /// `maxSessionMinutesFrom` in workout settings). Returns null only when there
  /// is no usable id — a reminder with no identity can't be scheduled or edited.
  static Reminder? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return Reminder.clamped(
      id: id,
      label: raw['label'] is String ? raw['label'] as String : '',
      kind: ReminderKind.fromName(raw['kind']),
      hour: (raw['hour'] as num?)?.toInt() ?? 8,
      minute: (raw['minute'] as num?)?.toInt() ?? 0,
      weekdays: {
        for (final d in (raw['weekdays'] as List? ?? const []))
          if (d is num) d.toInt(),
      },
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      sync: ReminderSync.fromMap(raw['sync']),
      emoji: raw['emoji'] is String ? raw['emoji'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.hour == hour &&
      other.minute == minute &&
      setEquals(other.weekdays, weekdays) &&
      other.enabled == enabled &&
      other.sync == sync &&
      other.emoji == emoji;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    kind,
    hour,
    minute,
    Object.hashAllUnordered(weekdays),
    enabled,
    sync,
    emoji,
  );
}

/// Decodes the stored `items` list into reminders, dropping any that can't be
/// read. The single source of truth for the settings document's shape.
List<Reminder> remindersFromStored(Object? raw) {
  if (raw is! List) return const [];
  final reminders = <Reminder>[];
  for (final item in raw) {
    final reminder = Reminder.fromMap(item);
    if (reminder != null) reminders.add(reminder);
  }
  return reminders;
}
