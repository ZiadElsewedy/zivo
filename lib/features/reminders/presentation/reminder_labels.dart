import 'package:flutter/widgets.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/util/date_format.dart';
import '../../../l10n/l10n.dart';
import '../domain/reminder.dart';
import '../domain/reminder_sync.dart';
import '../domain/workout_motivations.dart';

/// The presentation half of [ReminderKind] and the reminder's repeat schedule.
///
/// [ReminderKind] is a persisted id and carries no copy (see `reminder.dart`),
/// so its user-facing labels live here — the same domain→presentation split
/// `diet_labels.dart` and `workout_labels.dart` use.

String reminderKindLabel(BuildContext context, ReminderKind kind) =>
    switch (kind) {
      ReminderKind.general => l(context).remindersKindGeneral,
      ReminderKind.meal => l(context).remindersKindMeal,
      ReminderKind.workout => l(context).remindersKindWorkout,
    };

/// The voice a motivational workout reminder speaks in. [MotivationTone] is a
/// persisted id and carries no copy, so its labels live here.
String motivationToneLabel(BuildContext context, MotivationTone tone) =>
    switch (tone) {
      MotivationTone.gentle => l(context).remindersToneGentle,
      MotivationTone.toughLove => l(context).remindersToneToughLove,
      MotivationTone.hype => l(context).remindersToneHype,
    };

IconData reminderKindIcon(ReminderKind kind) => switch (kind) {
  ReminderKind.general => AppIcons.reminderGeneral,
  ReminderKind.meal => AppIcons.reminderMeal,
  ReminderKind.workout => AppIcons.reminderWorkout,
};

/// What a reminder's row leads with: the name the user typed, or the kind's
/// label when they left it blank.
String reminderDisplayLabel(BuildContext context, Reminder reminder) =>
    reminder.label.isNotEmpty
    ? reminder.label
    : reminderKindLabel(context, reminder.kind);

/// "6:30 AM" — the reminder's time, rendered through the locale's own clock.
String reminderTimeLabel(BuildContext context, Reminder reminder) =>
    formatClockTime(context, _timeAsDate(reminder.hour, reminder.minute));

/// "Mon" — the abbreviated weekday, from the locale (never a hand-rolled table).
String weekdayShortLabel(BuildContext context, int weekday) =>
    formatWeekdayShort(context, _dateForWeekday(weekday));

/// "Every day" or "Mon, Wed, Fri" — the repeat schedule as one short line.
String reminderRepeatSummary(BuildContext context, Reminder reminder) {
  if (reminder.isEveryDay) return l(context).remindersEveryDay;
  final days = reminder.effectiveWeekdays.toList()..sort();
  return days.map((d) => weekdayShortLabel(context, d)).join(', ');
}

/// A one-line description of a reminder's plan link for the row, or null for a
/// plain reminder: the synced meal's name, or the linked workout's next-up day
/// (falling back to a generic "synced" line when no day has been resolved yet).
String? reminderSyncSummary(BuildContext context, Reminder reminder) =>
    switch (reminder.sync) {
      MealSync m =>
        m.mealLabel.isNotEmpty ? m.mealLabel : l(context).remindersSyncedBadge,
      WorkoutSync w =>
        w.cachedDayLabel?.trim().isNotEmpty ?? false
            ? w.cachedDayLabel!.trim()
            : l(context).remindersSyncWorkout,
      null => null,
    };

/// A [DateTime] whose weekday is [weekday] (1..7), for formatting a weekday
/// name. 2024-01-01 was a Monday, so day (weekday) lands on the right one.
DateTime _dateForWeekday(int weekday) =>
    DateTime(2024, 1, 1).add(Duration(days: weekday - 1));

DateTime _timeAsDate(int hour, int minute) =>
    DateTime(2024, 1, 1, hour, minute);
