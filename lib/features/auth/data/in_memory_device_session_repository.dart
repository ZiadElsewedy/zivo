import 'dart:async';

import '../domain/active_session.dart';
import '../domain/device_session_repository.dart';

/// Offline/test [DeviceSessionRepository]: the active session per uid held in
/// memory and broadcast to watchers. Enough to exercise the takeover flow
/// without Firestore — a second `activate` for the same uid pushes to the first
/// device's stream exactly as the real backend would.
class InMemoryDeviceSessionRepository implements DeviceSessionRepository {
  final Map<String, ActiveSession?> _sessions = {};
  final Map<String, StreamController<ActiveSession?>> _controllers = {};

  StreamController<ActiveSession?> _controllerFor(String uid) =>
      _controllers.putIfAbsent(
        uid,
        () => StreamController<ActiveSession?>.broadcast(),
      );

  @override
  Future<void> activate(String uid, ActiveSession session) async {
    _sessions[uid] = session;
    _controllerFor(uid).add(session);
  }

  @override
  Stream<ActiveSession?> watch(String uid) async* {
    // Replay the current value to a late subscriber (as Firestore does), then
    // follow every change.
    yield _sessions[uid];
    yield* _controllerFor(uid).stream;
  }
}
