import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../domain/wallet.dart';
import '../domain/wallet_repository.dart';

/// The real [WalletRepository], backed by a single Firestore doc at
/// `users/{uid}/wallet/main`.
///
/// The uid-scoping, the cached `current`, the late-subscriber replay and the
/// always-on listener all live in [UidScopedMirror] — this is the
/// single-*document* shape of that mirror (the collection repositories mirror
/// a `List`; this one mirrors a nullable [Wallet]), so `signedOutValue` is
/// null rather than an empty list.
class FirestoreWalletRepository implements WalletRepository {
  FirestoreWalletRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<Wallet?>(
      uidSource: uidSource,
      signedOutValue: null,
      source: (uid) => _walletDoc(uid).snapshots().map(_fromDoc),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<Wallet?> _mirror;

  @override
  Wallet? get current => _mirror.current;

  @override
  Stream<Wallet?> watch() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> setBalance(int minor, {String currency = 'EGP'}) {
    final uid = uidSource.requireUid(this);
    return _walletDoc(uid).set({
      'balanceMinor': minor,
      'currency': currency,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> adjustBy(int deltaMinor) {
    final uid = uidSource.requireUid(this);
    final ref = _walletDoc(uid);
    // A transaction (not a cached `_current` check, nor a blind increment)
    // so this is correct even before any listener has observed a snapshot,
    // and so it never conjures a balance doc out of thin air when the user
    // hasn't set one up yet.
    return _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final balance = snapshot.data()?['balanceMinor'];
      if (balance is! int) return;
      tx.update(ref, {
        'balanceMinor': balance + deltaMinor,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DocumentReference<Map<String, dynamic>> _walletDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('wallet').doc('main');

  Wallet? _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final balance = data['balanceMinor'];
    final currency = data['currency'];
    final updatedAt = data['updatedAt'];
    if (balance is! int) return null;
    return Wallet(
      balanceMinor: balance,
      currency: currency is String ? currency : 'EGP',
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }
}
