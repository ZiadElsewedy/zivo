import '../domain/diet_day.dart';
import '../domain/diet_plan.dart';

/// Resolves which [DietDay] of [plan] applies on [date]: the day whose
/// `weekday` matches [date]'s, else the every-day template
/// (`weekday == null`), else — if the plan has exactly one day — that day.
/// Null when there's no plan or no day resolves unambiguously.
DietDay? dayForDate(DietPlan? plan, DateTime date) {
  if (plan == null) return null;
  final days = plan.days;
  for (final day in days) {
    if (day.weekday == date.weekday) return day;
  }
  for (final day in days) {
    if (day.weekday == null) return day;
  }
  if (days.length == 1) return days.single;
  return null;
}
