import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/auth/data/device_session_guard.dart';
import 'package:zivo/features/auth/data/in_memory_device_session_repository.dart';
import 'package:zivo/features/auth/domain/active_session.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

import '../support/fake_auth_repository.dart';

/// The single-device enforcement contract: claiming an account here makes this
/// device active, and a later claim from ANOTHER device invalidates this one —
/// signing it out and raising the reason flag — while an ordinary sign-out does
/// neither. All async, no widgets, no Firebase.
void main() {
  const user = AuthUser(uid: 'u1', email: 'you@zivo.app');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Let the guard's async claim (read device id → fire activate → start watch)
  // and any queued stream events settle.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('another device claiming the account signs this one out and flags why',
      () async {
    final repo = InMemoryDeviceSessionRepository();
    final auth = FakeAuthRepository(initial: const Authenticated(user));
    final guard = DeviceSessionGuard(authRepository: auth, repository: repo);
    addTearDown(guard.dispose);
    addTearDown(auth.dispose);

    guard.handleAuthChange('u1');
    await settle();
    // Claiming does not sign us out or raise the flag — we ARE the active one.
    expect(auth.signOutCount, 0);
    expect(guard.signedOutElsewhere.value, isFalse);

    // Device B claims the account with its own session id.
    await repo.activate(
      'u1',
      const ActiveSession(
        sessionId: 'device-b',
        deviceId: 'dB',
        platform: 'android',
      ),
    );
    await settle();

    expect(auth.signOutCount, 1, reason: 'stale device must sign out');
    expect(guard.signedOutElsewhere.value, isTrue);
  });

  test('a burst of foreign claims triggers exactly one sign-out', () async {
    final repo = InMemoryDeviceSessionRepository();
    final auth = FakeAuthRepository(initial: const Authenticated(user));
    final guard = DeviceSessionGuard(authRepository: auth, repository: repo);
    addTearDown(guard.dispose);
    addTearDown(auth.dispose);

    guard.handleAuthChange('u1');
    await settle();

    for (var i = 0; i < 3; i++) {
      await repo.activate(
        'u1',
        ActiveSession(sessionId: 'device-b-$i', deviceId: 'dB', platform: 'android'),
      );
    }
    await settle();

    expect(auth.signOutCount, 1);
  });

  test('an ordinary sign-out neither signs out again nor raises the flag',
      () async {
    final repo = InMemoryDeviceSessionRepository();
    final auth = FakeAuthRepository(initial: const Authenticated(user));
    final guard = DeviceSessionGuard(authRepository: auth, repository: repo);
    addTearDown(guard.dispose);
    addTearDown(auth.dispose);

    guard.handleAuthChange('u1');
    await settle();

    guard.handleAuthChange(null);
    await settle();

    expect(auth.signOutCount, 0);
    expect(guard.signedOutElsewhere.value, isFalse);

    // And after teardown, a stale ledger event can no longer sign us out.
    await repo.activate(
      'u1',
      const ActiveSession(sessionId: 'device-b', deviceId: 'dB', platform: 'android'),
    );
    await settle();
    expect(auth.signOutCount, 0);
  });

  test('re-claiming after a foreign takeover makes this device active again',
      () async {
    final repo = InMemoryDeviceSessionRepository();
    final auth = FakeAuthRepository(initial: const Authenticated(user));
    final guard = DeviceSessionGuard(authRepository: auth, repository: repo);
    addTearDown(guard.dispose);
    addTearDown(auth.dispose);

    guard.handleAuthChange('u1');
    await settle();
    await repo.activate(
      'u1',
      const ActiveSession(sessionId: 'device-b', deviceId: 'dB', platform: 'android'),
    );
    await settle();
    expect(auth.signOutCount, 1);

    // The user opens the app on this device again (a fresh run: uid seen anew).
    guard.handleAuthChange(null);
    guard.signedOutElsewhere.value = false;
    guard.handleAuthChange('u1');
    await settle();

    // Now this device is the active one; device B's session is no longer stored.
    // A stale event carrying device B's id would sign B out, not us — our own
    // re-claim matches what is stored, so no further sign-out here.
    expect(auth.signOutCount, 1);
    expect(guard.signedOutElsewhere.value, isFalse);
  });
}
