import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_scheduler.dart';
import '../domain/reminder.dart';
import '../domain/reminder_sync.dart';

/// One notification to schedule: [title] (with an optional [body]) at
/// [hour]:[minute], on [weekday] (1..7) or every day when [weekday] is null. The
/// pure plan the scheduler hands to the OS — extracted so the "how many alarms,
/// on which days, saying what" decision is testable without a platform channel.
typedef ReminderOccurrence = ({
  String title,
  String? body,
  int hour,
  int minute,
  int? weekday,
});

/// Resolves a reminder's notification title and body, folding in its sync:
/// a [MealSync] lists its customised items in the body; a [WorkoutSync] takes
/// the live next-up workout from [context] (and falls back to the reminder's own
/// label when no plan is resolved); a plain reminder is title-only, as before.
({String title, String? body}) resolveReminderText(
  Reminder reminder, {
  required String fallbackTitle,
  ReminderContext context = ReminderContext.empty,
}) {
  final labelled = reminder.label.trim();
  switch (reminder.sync) {
    case MealSync m:
      final title = labelled.isNotEmpty
          ? labelled
          : (m.mealLabel.isNotEmpty ? m.mealLabel : fallbackTitle);
      return (title: title, body: m.items.isEmpty ? null : m.items.join(' · '));
    case WorkoutSync _:
      final day = context.workoutTitle;
      if (day == null) {
        // No active plan / no next day resolved — behave like a plain reminder.
        return (
          title: labelled.isNotEmpty ? labelled : fallbackTitle,
          body: null,
        );
      }
      if (labelled.isNotEmpty) {
        final detail = context.workoutBody;
        return (title: labelled, body: detail == null ? day : '$day — $detail');
      }
      return (title: day, body: context.workoutBody);
    case null:
      return (title: labelled.isNotEmpty ? labelled : fallbackTitle, body: null);
  }
}

/// Expands enabled reminders into the concrete notifications to schedule: one
/// per every-day reminder, one per chosen weekday otherwise. Disabled reminders
/// produce nothing. [fallbackTitle] names a reminder the user left unlabelled;
/// [context] carries the live text for synced reminders.
List<ReminderOccurrence> reminderOccurrences(
  List<Reminder> reminders, {
  required String fallbackTitle,
  ReminderContext context = ReminderContext.empty,
}) {
  final occurrences = <ReminderOccurrence>[];
  for (final reminder in reminders) {
    if (!reminder.enabled) continue;
    final text = resolveReminderText(
      reminder,
      fallbackTitle: fallbackTitle,
      context: context,
    );
    if (reminder.isEveryDay) {
      occurrences.add((
        title: text.title,
        body: text.body,
        hour: reminder.hour,
        minute: reminder.minute,
        weekday: null,
      ));
    } else {
      for (final weekday in reminder.effectiveWeekdays) {
        occurrences.add((
          title: text.title,
          body: text.body,
          hour: reminder.hour,
          minute: reminder.minute,
          weekday: weekday,
        ));
      }
    }
  }
  return occurrences;
}

/// The real [NotificationScheduler], wrapping `flutter_local_notifications`.
///
/// Everything here is local: `zonedSchedule` hands the OS a repeating alarm and
/// the OS posts the notification even when ZIVO is not running. There is no
/// push, no APNs/FCM, no server (ADR-013).
///
/// **Inexact, on purpose.** Scheduling uses [AndroidScheduleMode.inexactAllowWhileIdle]
/// so the feature needs no `SCHEDULE_EXACT_ALARM` special-access grant — a meal
/// or workout nudge that lands a few minutes late is fine, and demanding
/// exact-alarm access for it would be the wrong trade.
class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;

  /// The Android channel reminders are posted on. Created lazily by the plugin
  /// on the first schedule.
  static const _channelId = 'zivo_reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription = 'Meal, workout and activity reminders.';

  @override
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    tz_data.initializeTimeZones();
    await _setLocalLocation();

    // No permission is requested here — the Darwin flags are all false so
    // launching the app never prompts. Permission is asked the first time the
    // user enables a reminder, in [requestPermission].
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<void> _setLocalLocation() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // If the device's zone can't be resolved, fall back to whatever
      // `timezone` defaults to rather than crashing setup — a reminder on the
      // wrong offset is far better than no scheduling at all.
    }
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  @override
  Future<void> reschedule(
    List<Reminder> reminders, {
    ReminderContext context = ReminderContext.empty,
  }) async {
    await init();
    // The stored reminders are the source of truth; the OS's scheduled set is a
    // pure mirror of them. Wiping and re-adding keeps it exact with no diffing,
    // and the ids below are only ever unique *within* one reschedule.
    await _plugin.cancelAll();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final occurrences = reminderOccurrences(
      reminders,
      fallbackTitle: _channelName,
      context: context,
    );
    var id = 0;
    for (final occ in occurrences) {
      // An every-day reminder (weekday == null) is one daily alarm matched on
      // time; a specific day is matched on day-of-week and time.
      final when = occ.weekday == null
          ? _nextInstanceOfTime(occ.hour, occ.minute)
          : _nextInstanceOfWeekdayTime(occ.weekday!, occ.hour, occ.minute);
      await _schedule(
        id: id++,
        title: occ.title,
        body: occ.body,
        when: when,
        match: occ.weekday == null
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
        details: details,
      );
    }
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String? body,
    required tz.TZDateTime when,
    required DateTimeComponents match,
    required NotificationDetails details,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: when,
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: match,
  );

  /// The next time [hour]:[minute] occurs in the device's zone — today if it is
  /// still ahead, tomorrow otherwise.
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// The next time [weekday] at [hour]:[minute] occurs, walking forward day by
  /// day (never with `Duration(days: 7)` maths that DST would skew).
  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
