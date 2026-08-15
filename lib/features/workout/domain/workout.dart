import 'exercise.dart';

/// A logged training session — an append-only log entity ("what happened").
class Workout {
  const Workout({
    required this.id,
    required this.title,
    required this.performedAt,
    required this.exercises,
    this.durationMinutes,
  });

  final String id;
  final String title; // e.g. "Push"
  final DateTime performedAt;
  final List<Exercise> exercises;
  final int? durationMinutes;

  int get exerciseCount => exercises.length;

  /// "Bench Press · Incline DB · Cable Fly" — the exercises as a single line.
  String get summary => exercises.map((e) => e.name).join(' · ');
}
