import 'dart:async';

import '../domain/university_item.dart';
import '../domain/university_item_type.dart';
import '../domain/university_repository.dart';

/// Demo store: keeps university items in memory and broadcasts changes.
/// Seeded with a due-today assignment, a next-week exam, and an undated item.
class InMemoryUniversityRepository implements UniversityRepository {
  InMemoryUniversityRepository() {
    _seed();
  }

  final List<UniversityItem> _items = [];
  final StreamController<List<UniversityItem>> _controller =
      StreamController<List<UniversityItem>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _items.addAll([
      UniversityItem(
        id: 'seed-u1',
        title: 'Assignment 2 — Algorithms',
        type: UniversityItemType.assignment,
        createdAt: now.subtract(const Duration(days: 2)),
        due: today,
        courseName: 'Algorithms',
      ),
      UniversityItem(
        id: 'seed-u2',
        title: 'Midterm — Data Structures',
        type: UniversityItemType.exam,
        createdAt: now.subtract(const Duration(days: 1)),
        due: today.add(const Duration(days: 7)),
        courseName: 'Data Structures',
      ),
      UniversityItem(
        id: 'seed-u3',
        title: 'Read Chapter 4 notes',
        type: UniversityItemType.assignment,
        createdAt: now,
      ),
    ]);
  }

  @override
  List<UniversityItem> get current => List.unmodifiable(_items);

  @override
  Stream<List<UniversityItem>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(UniversityItem item) async {
    _items.insert(0, item);
    _controller.add(current);
  }

  @override
  Future<void> update(UniversityItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    _items[index] = item;
    _controller.add(current);
  }

  @override
  Future<void> setDone(String id, bool done) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(done: done);
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((i) => i.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
