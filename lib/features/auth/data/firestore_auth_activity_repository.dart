import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/account_auth_metadata.dart';
import '../domain/auth_activity_repository.dart';
import '../domain/auth_event.dart';
import '../domain/auth_event_type.dart';

/// The real [AuthActivityRepository], backed by two Firestore locations:
///
///   users/{uid}/auth/account          — the always-current summary doc
///   users/{uid}/authEvents/{auto-id}  — the append-only fact log
///
/// This is the *only* auth place Firestore SDK types are allowed — everything
/// above consumes the domain models. Every method swallows its own errors:
/// bookkeeping must never break (or even delay a result from) a sign-in, so
/// callers fire-and-forget these calls.
class FirestoreAuthActivityRepository implements AuthActivityRepository {
  FirestoreAuthActivityRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  /// Resolved on first use, not at construction, so merely building this
  /// repository stays safe in environments where Firebase was never
  /// initialized (tests wire fakes instead; its methods are simply never
  /// called there).
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  final FirebaseFirestore? _firestoreOverride;

  /// Bumped when the shape of either location changes; lets future migrations
  /// branch on what a doc was written by.
  static const int _schemaVersion = 1;

  CollectionReference<Map<String, dynamic>> _accountsOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('auth');

  CollectionReference<Map<String, dynamic>> _eventsOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('authEvents');

  @override
  Future<void> recordAccountCreated({
    required String uid,
    required String provider,
    required String platform,
  }) => _guard(() async {
      final now = FieldValue.serverTimestamp();
      await _accountsOf(uid).doc('account').set({
        'schemaVersion': _schemaVersion,
        'createdAt': now,
        'registeredVia': provider,
        'registeredPlatform': platform,
        // A creation IS the account's first successful authentication.
        'lastSignInAt': now,
        'lastSignInVia': provider,
        'lastSignInPlatform': platform,
        'previousSignInAt': null,
        'signInCount': 1,
        'updatedAt': now,
      }, SetOptions(merge: true));
      await _appendEvent(
        uid,
        AuthEventType.accountCreated,
        provider: provider,
        platform: platform,
      );
    });

  @override
  Future<void> recordSignIn({
    required String uid,
    required String provider,
    required String platform,
    DateTime? fallbackCreatedAt,
  }) =>
      _guard(() async {
        // A transaction so two devices signing in concurrently can't clobber
        // each other's count or lose `previousSignInAt` to a stale read.
        await _firestore.runTransaction((tx) async {
          final ref = _accountsOf(uid).doc('account');
          final snap = await tx.get(ref);
          final existing = snap.exists ? snap.data() : null;
          final previous = _asDate(existing?['lastSignInAt']);

          if (existing == null) {
            // First summary write ever (the registration-era write was lost,
            // or this account predates tracking): create it, backfilling
            // createdAt from Firebase's own trusted metadata when available.
            tx.set(ref, {
              'schemaVersion': _schemaVersion,
              if (fallbackCreatedAt != null)
                'createdAt': Timestamp.fromDate(fallbackCreatedAt),
              'lastSignInAt': FieldValue.serverTimestamp(),
              'lastSignInVia': provider,
              'lastSignInPlatform': platform,
              'previousSignInAt': null,
              'signInCount': 1,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return;
          }

          final patch = <String, dynamic>{
            'schemaVersion': _schemaVersion,
            'lastSignInAt': FieldValue.serverTimestamp(),
            'lastSignInVia': provider,
            'lastSignInPlatform': platform,
            'previousSignInAt':
                previous == null ? null : Timestamp.fromDate(previous),
            'signInCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (existing['createdAt'] is! Timestamp &&
              fallbackCreatedAt != null) {
            patch['createdAt'] = Timestamp.fromDate(fallbackCreatedAt);
          }
          // update, not set(merge): only the session fields move; everything
          // else on the summary survives untouched.
          tx.update(ref, patch);
        });
        await _appendEvent(uid, AuthEventType.signIn,
            provider: provider, platform: platform);
      });

  @override
  Future<void> recordSignOut({required String uid}) =>
      _guard(() => _appendEvent(uid, AuthEventType.signOut));

  @override
  Future<void> recordPasswordChanged({required String uid}) =>
      _guard(() async {
        // Stamp the summary (owner-writable; the rules require schemaVersion)
        // and append the event, mirroring the server's markPasswordChanged.
        await _accountsOf(uid).doc('account').set({
          'schemaVersion': _schemaVersion,
          'lastPasswordChangeAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _appendEvent(uid, AuthEventType.passwordChanged,
            provider: 'password');
      });

  @override
  Future<void> recordEvent({
    required String uid,
    required AuthEventType type,
    String? provider,
    String? platform,
  }) => _guard(() => _appendEvent(uid, type, provider: provider, platform: platform));

  @override
  Stream<AccountAuthMetadata?> watchAccount(String uid) =>
      _accountsOf(uid).doc('account').snapshots().map(_fromSnap);

  @override
  Future<AccountAuthMetadata?> fetchAccount(String uid) async =>
      _fromSnap(await _accountsOf(uid).doc('account').get());

  @override
  Stream<List<AuthEvent>> watchRecentEvents({
    required String uid,
    int limit = 50,
  }) => _eventsOf(uid)
      .orderBy('occurredAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => s.docs
            .map(_eventFromSnap)
            .whereType<AuthEvent>()
            .toList(growable: false),
      );

  // --- helpers -------------------------------------------------------------

  Future<void> _appendEvent(
    String uid,
    AuthEventType type, {
    String? provider,
    String? platform,
  }) {
    return _eventsOf(uid).add({
      'schemaVersion': _schemaVersion,
      'type': type.id,
      'provider': ?provider,
      'platform': ?platform,
      'occurredAt': FieldValue.serverTimestamp(),
    });
  }

  AccountAuthMetadata? _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return AccountAuthMetadata(
      uid: snap.id == 'account'
          ? _uidFrom(snap.reference)
          : snap.id,
      createdAt: _asDate(data['createdAt']),
      registeredVia: _asString(data['registeredVia']),
      registeredPlatform: _asString(data['registeredPlatform']),
      lastSignInAt: _asDate(data['lastSignInAt']),
      lastSignInVia: _asString(data['lastSignInVia']),
      lastSignInPlatform: _asString(data['lastSignInPlatform']),
      previousSignInAt: _asDate(data['previousSignInAt']),
      signInCount: switch (data['signInCount']) {
        final int i => i,
        final num n => n.toInt(),
        _ => 0,
      },
      emailVerifiedAt: _asDate(data['emailVerifiedAt']),
      emailLastSentAt: _asDate(data['emailLastSentAt']),
      lastPasswordChangeAt: _asDate(data['lastPasswordChangeAt']),
    );
  }

  AuthEvent? _eventFromSnap(QueryDocumentSnapshot<Map<String, dynamic>> snap) {
    final type = AuthEventType.tryParse(snap.data()['type']);
    if (type == null) return null; // Unknown future kind — skip, don't crash.
    return AuthEvent(
      id: snap.id,
      type: type,
      occurredAt: _asDate(snap.data()['occurredAt']),
      provider: _asString(snap.data()['provider']),
      platform: _asString(snap.data()['platform']),
    );
  }

  /// The summary doc's uid comes from its parent path
  /// (`users/{uid}/auth/account`), not its own id.
  String _uidFrom(DocumentReference<Map<String, dynamic>> ref) =>
      ref.parent.parent?.id ?? '';

  /// Never throws on telemetry writes; surfaces failures in debug consoles.
  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      assert(() {
        debugPrint('FirestoreAuthActivityRepository: $e');
        return true;
      }());
    }
  }

  static DateTime? _asDate(Object? v) =>
      v is Timestamp ? v.toDate() : null;

  static String? _asString(Object? v) => v is String ? v : null;
}
