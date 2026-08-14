import 'schedule_event.dart';

/// The seam between the app and schedule storage (in-memory demo for now).
abstract interface class ScheduleRepository {
  List<ScheduleEvent> get current;
  Stream<List<ScheduleEvent>> watchAll();
  Future<void> add(ScheduleEvent event);
}

/// The current or next event to surface as Now/Next: the earliest event that
/// hasn't ended yet.
ScheduleEvent? nextRelevant(List<ScheduleEvent> events, DateTime now) {
  final upcoming = events.where((e) {
    final endsAt = e.end ?? e.start.add(const Duration(hours: 1));
    return endsAt.isAfter(now);
  }).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return upcoming.isEmpty ? null : upcoming.first;
}
