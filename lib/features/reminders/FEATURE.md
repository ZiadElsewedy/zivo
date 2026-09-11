# reminders — feature map

> Customizable **local** reminders: the user schedules a notification for a
> general activity, a meal, or a workout, and the OS fires it at that time. No
> push, no backend, no server (see [ADR-013](../../../docs/DECISIONS/ADR-013-local-notifications.md)).
> A meal or workout reminder can be **synced** to the user's plan — see below.

## Start here

- `domain/reminder.dart` — the `Reminder` entity (`label · kind · hour · minute ·
  weekdays · enabled · sync? · emoji?`) and `ReminderKind` (general/meal/workout, a
  persisted id with no copy; the retired `other` folds into `general` on decode).
  `weekdays` empty = every day. `emoji` (optional) leads the list row and the
  notification title. Map codec + `remindersFromStored`.
- `domain/reminder_sync.dart` — the optional plan link (`ReminderSync?` on a
  reminder; `null` = plain). Sealed: **`MealSync`** (a snapshot — which plan meal +
  the customised item lines shown in the notification body) and **`WorkoutSync`** (a
  live link — text is re-resolved from the active plan's next-up day at reschedule
  time; `cachedDayLabel` is only for the row). `WorkoutSync.motivational` swaps the
  exercise list for one line of encouragement — the day is still named, the lifts
  are not — in the reminder's chosen `tone`.
- `domain/workout_motivations.dart` — the **local** motivational copy (EN + AR,
  index-aligned within a tone) a motivational `WorkoutSync` shows, in three
  `MotivationTone`s (gentle / tough-love / hype), plus the pure, deterministic
  `pickWorkoutMotivation(seed, languageCode, tone)`. No network, no backend. The app
  root picks one line **per tone** per calendar day (seeded so the choice is stable
  across a reschedule) and hands them in via `ReminderContext.workoutMotivations`
  (a tone→line map, since tone is per-reminder but the context is shared).
- `domain/reminder_notification_text.dart` — the pure `resolveReminderText`
  (reminder + `ReminderContext` → notification title/body). Domain-only deps, so
  **both** the real scheduler (baking the OS notification) and the edit sheet's
  live preview call the *same* function — they can never disagree on what will
  fire.
- `domain/reminders_repository.dart` — the storage seam (`current`/`watch`/`save`),
  same shape as `WorkoutSettingsRepository`.
- `domain/notification_scheduler.dart` — the platform seam (`init`/
  `requestPermission`/`reschedule(reminders, {context})`) with
  `NoOpNotificationScheduler` for offline/tests. **`ReminderContext`** carries the
  live next-up workout text (and motivational line) a `WorkoutSync` needs, resolved
  by the app root so this layer depends on no repository.
- `presentation/pages/reminders_page.dart` — the one screen, reached from Settings.
  A synced reminder's row carries a small "synced" line (the meal, or the linked
  workout day).
- `presentation/widgets/edit_reminder_sheet.dart` — create/edit sheet. The time
  field is an **iOS-style `CupertinoDatePicker` wheel** in a `showZivoSheet`. A meal
  kind shows **"Sync from your plan"** (opens `_MealPickerSheet`, then an editable
  item checklist — add/remove only shapes the reminder, never the diet plan); a
  workout kind shows a **"Sync with my plan"** toggle, and — once synced — a nested
  **"Motivational message"** toggle plus a **tone selector** (Gentle / Tough love /
  Hype). Every kind offers an optional **emoji** picker (`_EmojiPicker`, a curated
  preset row). A **live notification preview** (`_NotificationPreview`,
  a lock-screen banner mock) sits above the time field and updates as you type/toggle,
  resolved through the shared `resolveReminderText` so it shows exactly what will fire
  (including today's motivational line). The header carries an explicit **close button**
  (`_SheetCloseButton`) — the reliable way out of a tall, keyboard-lifted sheet that
  leaves no scrim to tap. Selection is deliberately
  **monochrome** — solid ink-fill chips, hue-less `neutralMark` accents, native
  (adaptive) switches, ember only on Save and the preview's app tile.
- `presentation/workout_reminder_context.dart` — `workoutReminderContext(plan, {motivation})`
  builds the `ReminderContext` (next-up day + short exercise line + motivation) from the
  active plan. Shared by the app root and the edit-sheet preview so both resolve identical
  text; kept out of the reminders *domain* because it imports the workout domain.
- `presentation/reminder_labels.dart` — the domain→presentation label split for
  `ReminderKind`, weekdays, time, the repeat summary, and `reminderSyncSummary`.

## Data

- `data/firestore_reminders_repository.dart` — one doc `users/{uid}/settings/reminders`
  (field `items`). The `settings/{settingId}` rule is schema-free, so **no rules
  change** was needed.
- `data/in_memory_reminders_repository.dart` — offline/test twin.
- `data/local_notification_scheduler.dart` — the real scheduler
  (`flutter_local_notifications` + `timezone` + `flutter_timezone`). The pure
  `reminderOccurrences()` plan (every-day → 1 alarm, else 1 per weekday) is
  extracted for testing without a platform channel. Scheduling is **inexact**
  (no `SCHEDULE_EXACT_ALARM`). Every notification carries a **Snooze** action
  (Android action + iOS category `zivo_reminder`) and a JSON payload of its
  title/body; a Snooze tap re-posts that content 10 min later. A tap while the app
  is alive lands in `_onNotificationResponse`; one while it is terminated lands in
  the top-level `@pragma('vm:entry-point') notificationSnoozeBackgroundHandler`
  (its own plugin + tz, fully guarded). The Snooze **label is hardcoded English**
  (like the channel name) — localising notification chrome would mean threading the
  locale into this repository-free layer; tracked as a follow-up.

## Wiring

- Injected in [`app.dart`](../../app/app.dart): Firestore repo + real scheduler on a
  Firestore run, in-memory + no-op otherwise. Exposed as `AppScope.reminders` /
  `AppScope.notifications` (both nullable).
- The OS's scheduled notifications are a **pure mirror** of the stored reminders:
  `app.dart` subscribes the scheduler to `reminders.watch()` **and**
  `workoutPlans.watchActivePlan()`, reschedules on either change, and passes a
  `ReminderContext` (the current next-up workout's title + a short exercise line) so
  a `WorkoutSync` reminder always shows today's rotation day. Reschedules are
  **deduped** — with no workout-synced reminder the context is empty, so unrelated
  plan writes never reach the platform channel. The OS holds notifications across
  launches, so there is no per-resume work.

## Gotchas

- **App-boot tests must inject** `reminders:` + `notifications:` — the un-injected
  defaults are Firestore-/platform-backed and reach a channel at construction
  (same rule the sleep repos follow).
- Permission is asked the first time the user enables a reminder (`requestPermission`),
  not at launch — the Darwin init flags are all false on purpose.
- Platform config lives in `AndroidManifest.xml` (POST_NOTIFICATIONS,
  RECEIVE_BOOT_COMPLETED, the two scheduled-notification receivers, **and
  `ActionBroadcastReceiver`** for background Snooze taps) and
  `ios/Runner/AppDelegate.swift` (the `UNUserNotificationCenter` delegate). `minSdk`
  26 already covers the plugin.
- A notification actually **firing — and its Snooze action — can only be verified
  on a real device.** The background Snooze path (app terminated) especially: it
  runs in a fresh isolate the tests never exercise.
- **A `WorkoutSync` reminder is only as fresh as the last reschedule.** The OS fires
  a pre-scheduled notification even when ZIVO is closed, so its baked text reflects
  the next-up day as of the last time the app rescheduled (open/resume, or a
  plan/cursor change) — it cannot recompute the rotation at fire time. This is the
  accepted local-only trade (owner decision); for a workout nudge the app is usually
  open around training, so it's usually current.
