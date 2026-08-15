/// A compact, human relative-due label for a [due] date, e.g. "Overdue",
/// "Due today", "Due tomorrow", or "Due 5 Sep". Null if there is no due date.
String? relativeDue(DateTime? due, DateTime now) {
  if (due == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  if (day.isBefore(today)) return 'Overdue';
  if (day == today) return 'Due today';
  if (day == today.add(const Duration(days: 1))) return 'Due tomorrow';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Due ${day.day} ${months[day.month - 1]}';
}
