import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/active_session.dart';
import '../domain/auth_repository.dart';
import '../domain/device_session_repository.dart';

/// Enforces **one account = one active device**.
///
/// When a device becomes authenticated (a fresh sign-in, or a persisted session
/// restored at launch) it *claims* the account: it generates a new [sessionId],
/// writes it to the account's active-session ledger via [DeviceSessionRepository]
/// — an atomic replace — and then *watches* that ledger. The moment the stored
/// [sessionId] is no longer this device's, another device has claimed the
/// account; this one is stale, so it signs out of Firebase Auth (which the app's
/// [AuthGate] turns into the login screen) and raises [signedOutElsewhere] so a
/// message can be shown.
///
/// Why this exists rather than leaning on Firebase Auth: Auth keeps every
/// device's token valid independently and offers no reliable cross-device
/// logout. The server-owned ledger is the single source of truth instead, and
/// the realtime listener is what makes a takeover reach the losing device
/// immediately.
///
/// The claim write is deliberately fire-and-forget: Firestore reflects it in the
/// local snapshot at once (so the watch matches without a round trip) and syncs
/// to the server in the background, so a cold/offline launch never stalls on it.
class DeviceSessionGuard {
  DeviceSessionGuard({
    required AuthRepository authRepository,
    required DeviceSessionRepository repository,
  }) : _auth = authRepository,
       _sessions = repository;

  final AuthRepository _auth;
  final DeviceSessionRepository _sessions;

  /// Raised (once) when this device was signed out because the account became
  /// active elsewhere. The login surface watches it to show the reason, then
  /// resets it. Distinct from an ordinary sign-out, which never sets it.
  final ValueNotifier<bool> signedOutElsewhere = ValueNotifier<bool>(false);

  static const _kDeviceId = 'zivo.session.device_id';

  /// The session id this device wrote when it last claimed the account. The
  /// active-vs-stale test is `remote.sessionId != _localSessionId`.
  String? _localSessionId;

  /// The uid this run has already claimed, so the once-per-run claim isn't
  /// repeated on every auth re-emission (e.g. a token refresh).
  String? _claimedUid;

  StreamSubscription<ActiveSession?>? _watchSub;

  /// Guards against re-entrancy while the sign-out triggered by a takeover is
  /// still settling.
  bool _invalidating = false;

  /// Drive this from the app's auth-state listener. [uid] is the signed-in user
  /// or null when signed out. Claims + watches on first sight of a uid this run;
  /// tears everything down on sign-out.
  void handleAuthChange(String? uid) {
    if (uid == null) {
      _stop();
      return;
    }
    if (uid == _claimedUid) return; // already active this run
    _claimedUid = uid;
    unawaited(_claimAndWatch(uid));
  }

  Future<void> _claimAndWatch(String uid) async {
    final deviceId = await _deviceId();
    // The user may have signed out (or switched) while we read the device id.
    if (_claimedUid != uid) return;
    final sessionId = _randomId();
    _localSessionId = sessionId;
    _invalidating = false;

    // Fire-and-forget: never let an offline/slow write stall launch. The local
    // snapshot reflects it immediately, so the watch below still matches.
    unawaited(
      _sessions
          .activate(
            uid,
            ActiveSession(
              sessionId: sessionId,
              deviceId: deviceId,
              platform: _platform,
            ),
          )
          .catchError((_) {}),
    );

    _watchSub?.cancel();
    _watchSub = _sessions.watch(uid).listen((remote) {
      if (remote == null) return; // ledger not written yet — nothing to judge
      final local = _localSessionId;
      if (local != null && remote.sessionId != local) _onTakenOver();
    }, onError: (_) {});
  }

  /// Another device claimed the account. Sign out so the gate returns to login,
  /// and flag why. Idempotent — a burst of ledger emissions triggers one logout.
  void _onTakenOver() {
    if (_invalidating) return;
    _invalidating = true;
    _watchSub?.cancel();
    _watchSub = null;
    _localSessionId = null;
    signedOutElsewhere.value = true;
    unawaited(_auth.signOut());
  }

  void _stop() {
    _watchSub?.cancel();
    _watchSub = null;
    _localSessionId = null;
    _claimedUid = null;
    _invalidating = false;
  }

  void dispose() {
    _stop();
    signedOutElsewhere.dispose();
  }

  /// A stable per-install id, generated once and kept in shared preferences.
  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = _randomId();
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  static String get _platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// 128 bits of cryptographically-strong randomness — collisions between two
  /// devices' session ids are not a risk we want to reason about.
  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
