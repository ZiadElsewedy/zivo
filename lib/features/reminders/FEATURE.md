# reminders — feature map

> Simple, customizable **local** reminders: the user schedules a notification for
> a meal, a workout, or any other activity, and the OS fires it at that time. No
> push, no backend, no server (see [ADR-013](../../../docs/DECISIONS/ADR-013-local-notifications.md)).

## Start here

- `domain/reminder.dart` — the `Reminder` entity (`label · kind · hour · minute ·
  weekdays · enabled`) and `ReminderKind` (meal/workout/other, a persisted id with
  no copy). `weekdays` empty = every day. Map codec + `remindersFromStored`.
- `domain/reminders_repository.dart` — the storage seam (`current`/`watch`/`save`),
  same shape as `WorkoutSettingsRepository`.
- `domain/notification_scheduler.dart` — the platform seam (`init`/
  `requestPermission`/`reschedule`) with `NoOpNotificationScheduler` for
  offline/tests.
- `presentation/pages/reminders_page.dart` — the one screen, reached from Settings.
- `presentation/widgets/edit_reminder_sheet.dart` — create/edit sheet.
- `presentation/reminder_labels.dart` — the domain→presentation label split for
  `ReminderKind`, weekdays, time and the repeat summary.

## Data

- `data/firestore_reminders_repository.dart` — one doc `users/{uid}/settings/reminders`
  (field `items`). The `settings/{settingId}` rule is schema-free, so **no rules
  change** was needed.
- `data/in_memory_reminders_repository.dart` — offline/test twin.
- `data/local_notification_scheduler.dart` — the real scheduler
  (`flutter_local_notifications` + `timezone` + `flutter_timezone`). The pure
  `reminderOccurrences()` plan (every-day → 1 alarm, else 1 per weekday) is
  extracted for testing without a platform channel. Scheduling is **inexact**
  (no `SCHEDULE_EXACT_ALARM`).

## Wiring

- Injected in [`app.dart`](../../app/app.dart): Firestore repo + real scheduler on a
  Firestore run, in-memory + no-op otherwise. Exposed as `AppScope.reminders` /
  `AppScope.notifications` (both nullable).
- The OS's scheduled notifications are a **pure mirror** of the stored reminders:
  `app.dart` subscribes the scheduler to `reminders.watch()` and reschedules on
  every change (edits, and the sign-in/sign-out re-scope). The OS holds them
  across launches, so there is no per-resume work.

## Gotchas

- **App-boot tests must inject** `reminders:` + `notifications:` — the un-injected
  defaults are Firestore-/platform-backed and reach a channel at construction
  (same rule the sleep repos follow).
- Permission is asked the first time the user enables a reminder (`requestPermission`),
  not at launch — the Darwin init flags are all false on purpose.
- Platform config lives in `AndroidManifest.xml` (POST_NOTIFICATIONS,
  RECEIVE_BOOT_COMPLETED, the two receivers) and `ios/Runner/AppDelegate.swift`
  (the `UNUserNotificationCenter` delegate). `minSdk` 26 already covers the plugin.
- A notification actually **firing** can only be verified on a real device.
