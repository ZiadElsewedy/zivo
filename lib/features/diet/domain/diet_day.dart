import 'meal.dart';

/// One day of a [DietPlan] — its ordered [Meal]s. `weekday` matches
/// `DateTime.weekday` (1 = Monday .. 7 = Sunday); `null` means the day is an
/// every-day template that applies regardless of weekday.
class DietDay {
  const DietDay({this.weekday, required this.label, required this.meals});

  final int? weekday;
  final String label;
  final List<Meal> meals;
}
