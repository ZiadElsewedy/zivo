import '../step_day_repository.dart';

/// The offline/test [StepDayRepository]. Keeps the last recorded total per day
/// in a map; [stepsFor] lets a test read back what was written.
class InMemoryStepDayRepository implements StepDayRepository {
  final Map<String, int> _byDay = {};

  @override
  Future<void> record(DateTime day, int steps) async {
    _byDay[stepDayKey(day)] = steps;
  }

  /// The steps recorded for [day], or null if none were.
  int? stepsFor(DateTime day) => _byDay[stepDayKey(day)];
}
