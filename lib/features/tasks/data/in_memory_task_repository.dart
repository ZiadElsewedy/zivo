import 'dart:async';

import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Demo store: keeps tasks in memory and broadcasts changes. Seeded with the
/// two tasks shown on the Today design (an overdue one and an undated one).
class InMemoryTaskRepository implements TaskRepository {
  InMemoryTaskRepository() {
    _seed();
  }

  final List<Task> _items = [];
  final StreamController<List<Task>> _controller =
      StreamController<List<Task>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      Task(
        id: 'seed-t1',
        title: 'Return library books',
        createdAt: now.subtract(const Duration(days: 3)),
        due: DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1)),
      ),
      Task(
        id: 'seed-t2',
        title: 'Renew gym membership',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);
  }

  @override
  List<Task> get current => List.unmodifiable(_items);

  @override
  Stream<List<Task>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(Task task) async {
    _items.insert(0, task);
    _controller.add(current);
  }

  @override
  Future<void> update(Task task) async {
    final index = _items.indexWhere((t) => t.id == task.id);
    if (index == -1) return;
    _items[index] = task;
    _controller.add(current);
  }

  @override
  Future<void> setDone(String id, bool done) async {
    final index = _items.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(done: done);
    _controller.add(current);
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((t) => t.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
