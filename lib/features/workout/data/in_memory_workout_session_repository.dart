import 'dart:async';

import '../domain/live_session.dart';
import '../domain/session_status.dart';
import '../domain/workout_session_repository.dart';

/// Demo store for live sessions, newest-started-first, broadcasting changes.
class InMemoryWorkoutSessionRepository implements WorkoutSessionRepository {
  final List<LiveSession> _items = [];
  final StreamController<List<LiveSession>> _controller =
      StreamController<List<LiveSession>>.broadcast();

  @override
  List<LiveSession> get current => List.unmodifiable(_items);

  @override
  Stream<List<LiveSession>> watchAll() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  LiveSession? get activeSession => _firstActive(current);

  @override
  Stream<LiveSession?> watchActiveSession() => watchAll().map(_firstActive);

  LiveSession? _firstActive(List<LiveSession> sessions) {
    for (final s in sessions) {
      if (s.status == SessionStatus.active) return s;
    }
    return null;
  }

  @override
  Future<void> saveSession(LiveSession session) async {
    final index = _items.indexWhere((s) => s.id == session.id);
    if (index == -1) {
      _items.insert(0, session);
    } else {
      _items[index] = session;
    }
    _items.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _controller.add(current);
  }

  @override
  Future<void> deleteSession(String id) async {
    _items.removeWhere((s) => s.id == id);
    _controller.add(current);
  }

  void dispose() {
    _controller.close();
  }
}
