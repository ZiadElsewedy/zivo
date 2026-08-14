import 'task.dart';

/// The seam between the app and task storage (in-memory demo for now,
/// Firestore-backed later).
abstract interface class TaskRepository {
  List<Task> get current;
  Stream<List<Task>> watchAll();
  Future<void> add(Task task);
  Future<void> setDone(String id, bool done);
}
