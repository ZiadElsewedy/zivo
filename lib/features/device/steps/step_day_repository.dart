/// A per-day snapshot of the device step count, keyed by calendar day.
///
/// **Groundwork, not yet consumed.** The step sensor only ever exposes *today's*
/// live count ([StepCounterService]) — there is no history to read — so the
/// Daily Readiness engine cannot use steps yet. This seam records one small
/// number per day (`users/{uid}/stepDays/{yyyy-MM-dd}` → `{steps}`) so a step
/// history accrues from now on and a later readiness pass can fold it in.
///
/// Write-only on purpose for v1: nothing reads it back yet, and adding read
/// methods before there is a reader would be speculative surface.
abstract interface class StepDayRepository {
  /// Records [steps] as the total for the calendar day of [day]. Best-effort:
  /// a signed-out or offline device simply does not write, and the same day is
  /// overwritten as the count grows — never appended.
  Future<void> record(DateTime day, int steps);
}

/// The `yyyy-MM-dd` document id for [day]'s local calendar date. Shared by the
/// repository impls and their tests so a snapshot always lands on one doc.
String stepDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
