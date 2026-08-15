import 'dart:async';

import '../domain/exercise.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';

/// Demo store for workouts, newest first. Seeded with a recent push session
/// so the history opens with something to show.
class InMemoryWorkoutRepository implements WorkoutRepository {
  InMemoryWorkoutRepository() {
    _seed();
  }

  final List<Workout> _items = [];
  final StreamController<List<Workout>> _controller =
      StreamController<List<Workout>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.add(
      Workout(
        id: 'seed-w1',
        title: 'Push',
        performedAt: now.subtract(const Duration(days: 1)),
        durationMinutes: 50,
        exercises: const [
          Exercise(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60),
          Exercise(name: 'Incline DB Press', sets: 3, reps: 10, weightKg: 22.5),
          Exercise(name: 'Cable Fly', sets: 3, reps: 12),
          Exercise(name: 'Rope Pushdown', sets: 3, reps: 15, weightKg: 25),
        ],
      ),
    );
  }

  @override
  List<Workout> get current => List.unmodifiable(_items);

  @override
  Stream<List<Workout>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(Workout workout) async {
    _items.insert(0, workout);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
