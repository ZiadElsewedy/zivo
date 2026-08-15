/// A time-anchored commitment — a state entity that drives Today's Now/Next.
class ScheduleEvent {
  const ScheduleEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.location,
    this.label,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;
  final String? label; // e.g. "Lecture", "Gym"; defaults to "Event" in the UI
}
