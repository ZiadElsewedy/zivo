import 'package:flutter/foundation.dart';

import 'reminder.dart';

/// The live, resolved context a reschedule needs to bake dynamic reminders.
///
/// A [WorkoutSync] reminder carries no schedule payload of its own — its text is
/// the user's *current* next-up workout, which changes as the rotation advances.
/// The app root resolves that from the active plan and hands it in here so the
/// scheduler (and the pure `reminderOccurrences` planner) stays free of any
/// repository dependency. Every field is nullable: no active plan, or a plan with
/// no next day, means a workout-synced reminder simply falls back to its own
/// label, exactly as a plain reminder would.
@immutable
class ReminderContext {
  const ReminderContext({
    this.workoutTitle,
    this.workoutBody,
    this.workoutMotivation,
  });

  /// The next-up workout day's name (e.g. "Push Day"), or null.
  final String? workoutTitle;

  /// A short line under it (e.g. "Bench · OHP · Dips +2 more"), or null.
  final String? workoutBody;

  /// The motivational line a [WorkoutSync] with `motivational` on shows instead
  /// of [workoutBody] (e.g. "Don't skip leg day."), or null. Picked once per day
  /// by the app root so the choice is stable across a reschedule; see
  /// `workout_motivations.dart`.
  final String? workoutMotivation;

  static const empty = ReminderContext();

  @override
  bool operator ==(Object other) =>
      other is ReminderContext &&
      other.workoutTitle == workoutTitle &&
      other.workoutBody == workoutBody &&
      other.workoutMotivation == workoutMotivation;

  @override
  int get hashCode =>
      Object.hash(workoutTitle, workoutBody, workoutMotivation);
}

/// The seam between the app and the platform's local-notification machinery —
/// the repository-seam philosophy applied to a device service rather than a
/// data store.
///
/// Presentation, wiring and tests depend on this interface only; the real
/// `flutter_local_notifications` implementation lives behind
/// `data/local_notification_scheduler.dart`, and `NoOpNotificationScheduler`
/// stands in for offline runs and every widget/unit test (which must never
/// touch a platform channel).
abstract interface class NotificationScheduler {
  /// One-time setup: initialise the plugin and the timezone database. Safe to
  /// call more than once.
  Future<void> init();

  /// Ask the OS for permission to post notifications, returning whether it was
  /// granted. Called the first time the user enables a reminder.
  Future<bool> requestPermission();

  /// Cancel everything currently scheduled and reschedule from [reminders].
  /// Cancel-all-then-reschedule keeps the OS's scheduled set an exact mirror of
  /// the stored reminders with no per-reminder diffing. [context] carries the
  /// live text for any synced reminder (see [ReminderContext]); the default is
  /// [ReminderContext.empty], under which synced reminders fall back to their
  /// own label.
  Future<void> reschedule(
    List<Reminder> reminders, {
    ReminderContext context = ReminderContext.empty,
  });
}

/// The offline/test [NotificationScheduler] — the contract, doing nothing. The
/// injected default when Firestore is off, and what every app-boot test wires so
/// booting `ZivoApp` never reaches a platform channel (the same reason the
/// sleep/session repositories are injected in those tests).
class NoOpNotificationScheduler implements NotificationScheduler {
  const NoOpNotificationScheduler();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> reschedule(
    List<Reminder> reminders, {
    ReminderContext context = ReminderContext.empty,
  }) async {}
}
