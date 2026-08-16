import 'dart:async';

import '../domain/schedule_event.dart';
import '../domain/schedule_repository.dart';

/// Demo store for schedule events. Seeded with a lecture a couple of hours out
/// so Today opens with a Now/Next card.
class InMemoryScheduleRepository implements ScheduleRepository {
  InMemoryScheduleRepository() {
    _seed();
  }

  final List<ScheduleEvent> _items = [];
  final StreamController<List<ScheduleEvent>> _controller =
      StreamController<List<ScheduleEvent>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.add(
      ScheduleEvent(
        id: 'seed-ev1',
        title: 'Data Structures',
        label: 'Lecture',
        start: now.add(const Duration(hours: 2)),
        end: now.add(const Duration(hours: 3)),
        location: 'Hall B',
      ),
    );
  }

  @override
  List<ScheduleEvent> get current => List.unmodifiable(_items);

  @override
  Stream<List<ScheduleEvent>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(ScheduleEvent event) async {
    _items.add(event);
    _controller.add(current);
  }

  @override
  Future<void> update(ScheduleEvent event) async {
    final index = _items.indexWhere((e) => e.id == event.id);
    if (index == -1) return;
    _items[index] = event;
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
