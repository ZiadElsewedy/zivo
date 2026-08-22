import 'dart:async';

import '../domain/body_weight_entry.dart';
import '../domain/body_weight_repository.dart';

/// Demo store for bodyweight entries, newest-logged-first, broadcasting
/// changes. [seed] pre-populates it at construction; production callers
/// just omit it.
class InMemoryBodyWeightRepository implements BodyWeightRepository {
  InMemoryBodyWeightRepository({List<BodyWeightEntry> seed = const []}) {
    _items
      ..addAll(seed)
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  final List<BodyWeightEntry> _items = [];
  final StreamController<List<BodyWeightEntry>> _controller =
      StreamController<List<BodyWeightEntry>>.broadcast();

  @override
  List<BodyWeightEntry> get current => List.unmodifiable(_items);

  @override
  Stream<List<BodyWeightEntry>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> save(BodyWeightEntry entry) async {
    final index = _items.indexWhere((e) => e.id == entry.id);
    if (index == -1) {
      _items.add(entry);
    } else {
      _items[index] = entry;
    }
    _items.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    _controller.add(current);
  }

  void dispose() {
    _controller.close();
  }
}
