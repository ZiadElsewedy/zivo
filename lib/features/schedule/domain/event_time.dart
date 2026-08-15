import 'schedule_event.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// "09:30", derived from an event's start.
String clockLabel(ScheduleEvent e) => '${_two(e.start.hour)}:${_two(e.start.minute)}';

/// A relative label for Now/Next: "in 2h", "in 45m", "now", or "" when past.
String relativeLabel(ScheduleEvent e, DateTime now) {
  final diff = e.start.difference(now);
  if (diff.isNegative) {
    final end = e.end ?? e.start.add(const Duration(hours: 1));
    return end.isAfter(now) ? 'now' : '';
  }
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes}m';
  return 'in ${diff.inHours}h';
}

/// Combined "09:30 · in 2h" (or just "09:30" when there's no relative part).
String eventTimeLabel(ScheduleEvent e, DateTime now) {
  final rel = relativeLabel(e, now);
  return rel.isEmpty ? clockLabel(e) : '${clockLabel(e)} · $rel';
}
