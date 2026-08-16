import 'workout.dart';

/// The seam between the app and workout storage (in-memory demo for now).
abstract interface class WorkoutRepository {
  List<Workout> get current;
  Stream<List<Workout>> watchAll();
  Future<void> add(Workout workout);
  Future<void> update(Workout workout);
  Future<void> remove(String id);
}
