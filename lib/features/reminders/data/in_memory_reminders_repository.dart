import 'dart:async';

import '../domain/reminder.dart';
import '../domain/reminders_repository.dart';

/// The offline/test [RemindersRepository] — the same contract without Firestore.
class InMemoryRemindersRepository implements RemindersRepository {
  InMemoryRemindersRepository({List<Reminder>? initial})
    : _reminders = List.unmodifiable(initial ?? const []);

  List<Reminder> _reminders;
  final _controller = StreamController<List<Reminder>>.broadcast();

  @override
  List<Reminder> get current => _reminders;

  @override
  Stream<List<Reminder>> watch() async* {
    yield _reminders;
    yield* _controller.stream;
  }

  @override
  Future<void> save(List<Reminder> reminders) async {
    _reminders = List.unmodifiable(reminders);
    _controller.add(_reminders);
  }

  void dispose() => _controller.close();
}
