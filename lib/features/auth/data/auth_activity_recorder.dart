import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../domain/auth_activity_repository.dart';
import 'mappers/firebase_user_mapper.dart';

/// Auth bookkeeping, as a thing of its own.
///
/// Every successful authentication should leave a trace: an account-summary
/// update and an append to the audit log. That is a genuine requirement, and
/// it is also completely subordinate to the operation it describes — **a lost
/// telemetry write must never fail a sign-in**. So every method here is
/// deliberately `void`, never awaited, and swallows its own errors.
///
/// Extracted from the repository because it is the one concern in the auth
/// data layer with a different failure contract from everything around it.
/// Inline, that contract was enforced by remembering to write `unawaited(...)`
/// at seven call sites; here it is enforced by the signatures.
///
/// A null [repository] (offline runs, tests) makes every method a no-op, which
/// is why the repository never has to null-check before recording.
class AuthActivityRecorder {
  const AuthActivityRecorder(this._repository);

  final AuthActivityRepository? _repository;

  /// The device label recorded with client-written events.
  static String get platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// Records a federated authentication, distinguishing an account's very
  /// first one from every later one.
  ///
  /// Email flows know statically which they are; a federated flow cannot —
  /// "sign in" and "sign up" are the same button. Firebase's server-side
  /// `isNewUser` flag is the only trustworthy answer, and it is only available
  /// on the credential, right here.
  void federatedSession(fb.UserCredential cred) {
    final provider =
        cred.additionalUserInfo?.providerId ?? AuthProviderIds.google;
    if (cred.additionalUserInfo?.isNewUser ?? false) {
      accountCreated(cred, provider: provider);
    } else {
      session(cred, provider: provider);
    }
  }

  /// Records that an account came into existence.
  void accountCreated(fb.UserCredential cred, {required String provider}) {
    final uid = cred.user?.uid;
    final repo = _repository;
    if (uid == null || repo == null) return;
    _fire(
      repo.recordAccountCreated(
        uid: uid,
        provider: provider,
        platform: platformName,
      ),
    );
  }

  /// Records a successful authentication on an existing account.
  ///
  /// Carries Firebase's own server-side creation time so a summary document
  /// missing `createdAt` — the registration-era write was lost offline, say —
  /// is backfilled from truth rather than from whenever we noticed.
  void session(fb.UserCredential cred, {required String provider}) {
    final user = cred.user;
    final repo = _repository;
    if (user == null || repo == null) return;
    _fire(
      repo.recordSignIn(
        uid: user.uid,
        provider: provider,
        platform: platformName,
        fallbackCreatedAt: user.metadata.creationTime,
      ),
    );
  }

  /// Records an explicit session end. Called BEFORE the identity is torn down,
  /// since the write needs a uid to address.
  void signOut(String uid) {
    final repo = _repository;
    if (repo == null) return;
    _fire(repo.recordSignOut(uid: uid));
  }

  /// Records an in-app password change. (The signed-out reset flow records its
  /// own server-side equivalent — the user has no session to write from.)
  void passwordChanged(String uid) {
    final repo = _repository;
    if (repo == null) return;
    _fire(repo.recordPasswordChanged(uid: uid));
  }

  /// Fire-and-forget with the failure contract made explicit: not awaited, and
  /// a rejection is dropped rather than propagated into the caller's future.
  void _fire(Future<void> write) {
    unawaited(write.catchError((_) {}));
  }
}
