/// One consumption-log record — "meal [mealId] was eaten on [day]". Persisted
/// as `dietEntries/{dayKey}__{mealId}`; toggling `eaten` never deletes the
/// doc, it flips the field (see [DietRepository.setMealEaten]).
class DietEntry {
  const DietEntry({required this.mealId, required this.day, required this.eaten});

  final String mealId;
  final DateTime day;
  final bool eaten;
}
