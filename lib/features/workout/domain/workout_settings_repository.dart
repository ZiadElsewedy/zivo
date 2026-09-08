import 'workout_settings.dart';

/// The seam between the app and the account's workout preferences. Same shape
/// as `MediaPreferencesRepository`: a single settings document, re-scoped as
/// the signed-in uid changes, emitting [WorkoutSettings.defaults] when signed
/// out so nothing downstream ever has to handle a null.
abstract interface class WorkoutSettingsRepository {
  /// The last known settings — [WorkoutSettings.defaults] until the first read
  /// lands, so a synchronous caller (the staleness sweep) always has a
  /// threshold to work with.
  WorkoutSettings get current;

  Stream<WorkoutSettings> watch();

  Future<void> save(WorkoutSettings settings);
}
