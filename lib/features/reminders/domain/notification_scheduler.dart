import 'reminder.dart';

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
  /// the stored reminders with no per-reminder diffing.
  Future<void> reschedule(List<Reminder> reminders);
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
  Future<void> reschedule(List<Reminder> reminders) async {}
}
