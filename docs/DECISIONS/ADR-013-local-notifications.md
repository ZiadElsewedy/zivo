# ADR-013 — Local reminders: on-device notifications, no push

**Status:** accepted · 2026-09-11
**Context:** [`lib/features/reminders/`](../../lib/features/reminders/FEATURE.md) ·
adds three dependencies · no `firestore.rules` change

## Context

ZIVO had no notification system. The owner asked for the simplest, most
practical version: the user sets a time for a meal or a workout (or anything
else), and the app reminds them at that time. Nothing more — no push campaigns,
no server-driven nudges, no engagement loop.

## Decision

**Local notifications only, scheduled on-device.** A reminder is one flat model
— `label · kind · time · repeat-days · on/off` — and one model covers meals,
workouts and "other" alike. They live in one place (a **Reminders** page reached
from Settings), not scattered into per-feature settings screens.

The stored reminders are the single source of truth; the OS's scheduled
notifications are a **pure mirror** of them, kept in sync by a
cancel-all-then-reschedule on every change, wired at app root off
`reminders.watch()`.

### Three dependencies, and why each pays rent

- **`flutter_local_notifications`** — the one maintained way to schedule an OS
  notification from Flutter. There is no lighter alternative that survives the
  app being closed.
- **`timezone`** + **`flutter_timezone`** — `zonedSchedule` needs a `TZDateTime`.
  `timezone` carries the zone database; `flutter_timezone` reports the device's
  zone. Together they make a daily reminder fire at the right *wall-clock* time
  across DST — the same DST-correctness posture as [ADR-012](ADR-012-streaks-and-session-duration.md)
  and `core/util/calendar.dart`.

### The seams

Two interfaces keep the feature testable and swappable, per the repository-seam
rule: `RemindersRepository` (Firestore / in-memory) for storage, and
`NotificationScheduler` (real `flutter_local_notifications` / no-op) for the
platform. Off Firestore, and in every test, both are the offline variant, so
booting the app never reaches a platform channel.

## Consequences / constraints

- **Scheduling is inexact** (`AndroidScheduleMode.inexactAllowWhileIdle`). A
  meal or workout nudge that lands a few minutes late is fine, and demanding the
  `SCHEDULE_EXACT_ALARM` special-access grant for it would be the wrong trade.
- **Permission is asked on first enable**, not at launch (the Darwin init flags
  are all false). A denied grant surfaces a note; it never blocks saving.
- **No `firestore.rules` change**: reminders live at `users/{uid}/settings/reminders`,
  and that collection's rule is deliberately schema-free.
- **Owner-side**: the platform config is in the repo (`AndroidManifest.xml`,
  `AppDelegate.swift`); `minSdk` 26 already satisfies the plugin. That a
  notification actually *fires* at the set time can only be verified on a real
  device — the offline scheduler and the extracted pure `reminderOccurrences()`
  plan cover everything a test can.

## Explicitly out of scope

Push / remote notifications, snooze, actionable/rich notifications, per-reminder
sounds, auto-generating reminders from the diet plan, and any streak/engagement
logic. If a later need arises, the `NotificationScheduler` seam is where a native
layer would go.
