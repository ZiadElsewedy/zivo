import 'reminder.dart';

/// The seam between the app and the account's local reminders. Same shape as
/// [WorkoutSettingsRepository]: one settings document, re-scoped as the
/// signed-in uid changes, emitting an empty list when signed out so nothing
/// downstream ever has to handle a null.
abstract interface class RemindersRepository {
  /// The last known reminders — empty until the first read lands, so a
  /// synchronous caller always has a list to work with.
  List<Reminder> get current;

  Stream<List<Reminder>> watch();

  Future<void> save(List<Reminder> reminders);
}
