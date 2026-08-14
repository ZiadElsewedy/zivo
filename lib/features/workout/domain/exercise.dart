/// A single movement within a workout: sets × reps at an optional load.
class Exercise {
  const Exercise({
    required this.name,
    required this.sets,
    required this.reps,
    this.weightKg,
  });

  final String name;
  final int sets;
  final int reps;
  final double? weightKg;
}
