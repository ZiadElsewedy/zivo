import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_scheduler.dart';
import '../domain/reminder.dart';
import '../domain/reminder_notification_text.dart';

/// The action button ids and the snooze delay, shared by the scheduler and its
/// background tap handler.
const String _snoozeActionId = 'zivo_snooze';
const String _reminderCategoryId = 'zivo_reminder';
const Duration _snoozeDelay = Duration(minutes: 10);

/// Snoozed re-posts are scheduled with ids from this base up, well clear of the
/// mirror's `0..N` ids so a snooze never collides with a scheduled reminder.
const int _snoozeIdBase = 900000;

/// The Android channel a snoozed re-post reuses (same as the scheduled one).
const String _channelId = 'zivo_reminders';
const String _channelName = 'Reminders';
const String _channelDescription = 'Meal, workout and activity reminders.';

/// The user-facing label on the Snooze action button. Hardcoded English, the
/// same trade the channel name makes — localising notification chrome would mean
/// threading the current locale down to this repository-free layer. Tracked as a
/// follow-up.
const String _snoozeLabel = 'Snooze';

/// Handles a tap on the **Snooze** action from a *background* isolate — the case
/// where the OS posted the notification while ZIVO was terminated. It must be a
/// top-level, `vm:entry-point` function: the plugin spins up a fresh isolate
/// with none of the app's state, so this re-creates its own plugin + timezone
/// and re-posts the reminder [_snoozeDelay] later. Best-effort and fully
/// guarded — a failure here must never crash the isolate.
@pragma('vm:entry-point')
void notificationSnoozeBackgroundHandler(NotificationResponse response) {
  if (response.actionId != _snoozeActionId) return;
  // Fire-and-forget: the isolate is torn down after this returns, so we just
  // kick off the async re-post and let it run.
  _postSnooze(FlutterLocalNotificationsPlugin(), response.payload);
}

/// Re-posts a snoozed reminder [_snoozeDelay] from now, reading the title/body
/// back out of the notification's [payload]. Shared by the foreground and
/// background handlers. Any failure is swallowed — a snooze that silently
/// doesn't fire is far better than a crash.
Future<void> _postSnooze(
  FlutterLocalNotificationsPlugin plugin,
  String? payload,
) async {
  try {
    final decoded = payload == null ? null : jsonDecode(payload);
    if (decoded is! Map) return;
    final title = decoded['t'];
    if (title is! String || title.isEmpty) return;
    final body = decoded['b'] is String ? decoded['b'] as String : null;

    // The background isolate has no timezone data loaded; the foreground one
    // already does, but re-initialising is cheap and idempotent.
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Fall back to the package default zone rather than dropping the snooze.
    }

    final when = tz.TZDateTime.now(tz.local).add(_snoozeDelay);
    await plugin.zonedSchedule(
      // A distinct id per snooze so two snoozes don't overwrite each other.
      id: _snoozeIdBase + DateTime.now().millisecondsSinceEpoch.remainder(90000),
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _notificationDetails(payload: payload),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  } catch (_) {
    // Never let a malformed payload or a platform hiccup take down the isolate.
  }
}

/// The notification presentation shared by scheduled reminders and snoozed
/// re-posts: high-importance, with a **Snooze** action on both platforms. The
/// [payload] rides along so a later Snooze tap can re-post the same content.
NotificationDetails _notificationDetails({String? payload}) => NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    importance: Importance.high,
    priority: Priority.high,
    actions: const [
      // showsUserInterface:false → handled in the background without opening the
      // app; cancelNotification:true → the tapped banner clears on snooze.
      AndroidNotificationAction(
        _snoozeActionId,
        _snoozeLabel,
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ],
  ),
  iOS: DarwinNotificationDetails(categoryIdentifier: _reminderCategoryId),
);

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

  @override
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    tz_data.initializeTimeZones();
    await _setLocalLocation();

    // No permission is requested here — the Darwin flags are all false so
    // launching the app never prompts. Permission is asked the first time the
    // user enables a reminder, in [requestPermission]. The iOS category carries
    // the Snooze action; its Android twin is attached per-notification instead.
    // Not const: DarwinNotificationAction.plain is a factory, not a const ctor.
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _reminderCategoryId,
            actions: [
              DarwinNotificationAction.plain(_snoozeActionId, _snoozeLabel),
            ],
          ),
        ],
      ),
    );
    await _plugin.initialize(
      settings: settings,
      // A Snooze tap while the app is alive lands here; one while it is
      // terminated lands in the top-level background handler.
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          notificationSnoozeBackgroundHandler,
    );
  }

  /// Foreground/background-alive tap handling: a Snooze action re-posts the
  /// reminder; a plain tap is left to the OS's default (open the app).
  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == _snoozeActionId) {
      _postSnooze(_plugin, response.payload);
    }
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
    // and the ids below are only ever unique *within* one reschedule. (A pending
    // snooze is wiped too — an acceptable edge, since a reschedule means the
    // reminders or plan just changed.)
    await _plugin.cancelAll();

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
      );
    }
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String? body,
    required tz.TZDateTime when,
    required DateTimeComponents match,
  }) {
    // The payload carries the resolved text so a Snooze tap can re-post it.
    final fields = <String, String>{'t': title};
    if (body != null) fields['b'] = body;
    final payload = jsonEncode(fields);
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _notificationDetails(payload: payload),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: match,
      payload: payload,
    );
  }

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
