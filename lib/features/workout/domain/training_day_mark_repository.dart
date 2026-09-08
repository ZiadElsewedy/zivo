import 'training_day_mark.dart';

/// The seam between the app and the per-calendar-day training marks —
/// missed-day reasons and spent streak restores, one document per day.
///
/// Separate from [WorkoutSessionRepository] on purpose, and that separation is
/// the whole safety argument for the restore feature: a restore that were
/// stored as a synthetic session would have to be filtered out of roughly
/// fifteen call sites (averages, volume, PRs, adherence, the AI's fact sheet)
/// and out of every one written later. Kept in its own collection, "a restore
/// is not a workout" stops being a convention somebody has to remember and
/// becomes a fact about where the bytes live.
abstract interface class TrainingDayMarkRepository {
  List<TrainingDayMark> get current;
  Stream<List<TrainingDayMark>> watchAll();

  /// Creates or replaces the mark for its day (idempotent — the key is the
  /// calendar day).
  Future<void> saveMark(TrainingDayMark mark);

  /// Removes the mark for [day]'s calendar day, if any.
  Future<void> deleteMark(DateTime day);
}
