import 'dart:async';

import '../../../core/util/calendar.dart';
import '../domain/training_day_mark.dart';
import '../domain/training_day_mark_repository.dart';

/// The offline/test [TrainingDayMarkRepository] — one entry per calendar day,
/// newest first.
class InMemoryTrainingDayMarkRepository implements TrainingDayMarkRepository {
  InMemoryTrainingDayMarkRepository({List<TrainingDayMark> seed = const []}) {
    for (final mark in seed) {
      _items[dayKey(mark.day)] = mark;
    }
  }

  final Map<String, TrainingDayMark> _items = {};
  final StreamController<List<TrainingDayMark>> _controller =
      StreamController<List<TrainingDayMark>>.broadcast();

  @override
  List<TrainingDayMark> get current {
    final list = _items.values.toList()..sort((a, b) => b.day.compareTo(a.day));
    return List.unmodifiable(list);
  }

  @override
  Stream<List<TrainingDayMark>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> saveMark(TrainingDayMark mark) async {
    _items[mark.key] = mark;
    _controller.add(current);
  }

  @override
  Future<void> deleteMark(DateTime day) async {
    _items.remove(dayKey(day));
    _controller.add(current);
  }

  void dispose() => _controller.close();
}
