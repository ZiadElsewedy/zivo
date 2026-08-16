import 'dart:async';

import '../domain/moment.dart';
import '../domain/moment_repository.dart';

/// Demo store for moments, newest first. Seeded with one captioned moment.
class InMemoryMomentRepository implements MomentRepository {
  InMemoryMomentRepository() {
    _seed();
  }

  final List<Moment> _items = [];
  final StreamController<List<Moment>> _controller =
      StreamController<List<Moment>>.broadcast();

  void _seed() {
    final now = DateTime.now();
    _items.add(
      Moment(
        id: 'seed-m1',
        caption: 'First sketch of the ZIVO home screen.',
        takenAt: now.subtract(const Duration(days: 1)),
      ),
    );
  }

  @override
  List<Moment> get current => List.unmodifiable(_items);

  @override
  Stream<List<Moment>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> add(Moment moment) async {
    _items.insert(0, moment);
    _controller.add(current);
  }

  @override
  Future<void> update(Moment moment) async {
    final index = _items.indexWhere((m) => m.id == moment.id);
    if (index == -1) return;
    _items[index] = moment;
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((m) => m.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
