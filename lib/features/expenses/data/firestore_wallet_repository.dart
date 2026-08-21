import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/wallet.dart';
import '../domain/wallet_repository.dart';

/// The real [WalletRepository], backed by a single Firestore doc at
/// `users/{uid}/wallet/main`. See `FirestoreExpenseRepository` for the
/// uid-rescoping pattern this mirrors.
class FirestoreWalletRepository implements WalletRepository {
  FirestoreWalletRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  Wallet? _current;
  bool _hasSnapshot = false;
  StreamController<Wallet?>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  @override
  Wallet? get current => _current;

  @override
  Stream<Wallet?> watch() async* {
    _controller ??= StreamController<Wallet?>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    if (_hasSnapshot) yield _current;
    yield* _controller!.stream;
  }

  void _start() {
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  void _stop() {
    _uidSub?.cancel();
    _uidSub = null;
    _docSub?.cancel();
    _docSub = null;
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onUidChanged(String? uid) {
    _docSub?.cancel();
    if (uid == null) {
      _emit(null);
      return;
    }
    _docSub = _walletDoc(uid).snapshots().listen((snapshot) {
      _emit(_fromDoc(snapshot));
    }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(Wallet? wallet) {
    _current = wallet;
    _hasSnapshot = true;
    _controller?.add(_current);
  }

  @override
  Future<void> setBalance(int minor, {String currency = 'EGP'}) {
    final uid = _requireUid();
    return _walletDoc(uid).set({
      'balanceMinor': minor,
      'currency': currency,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> adjustBy(int deltaMinor) {
    final uid = _requireUid();
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

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreWalletRepository: no signed-in user.');
    }
    return uid;
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
