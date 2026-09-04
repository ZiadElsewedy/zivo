import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../domain/expense.dart';
import '../domain/expense_repository.dart';

/// The real [ExpenseRepository], backed by Firestore's `users/{uid}/expenses`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Expense] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
class FirestoreExpenseRepository implements ExpenseRepository {
  FirestoreExpenseRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<Expense>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _expensesCollection(uid)
          .orderBy('spentAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<Expense>> _mirror;

  @override
  List<Expense> get current => List.unmodifiable(_mirror.current);

  @override
  Stream<List<Expense>> watchAll() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> add(Expense expense) {
    final uid = uidSource.requireUid(this);
    return _expensesCollection(uid).doc(expense.id).set({
      'amountMinor': expense.amountMinor,
      'currency': expense.currency,
      'category': expense.categoryId,
      'spentAt': Timestamp.fromDate(expense.spentAt),
      'note': expense.note,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(Expense expense) {
    final uid = uidSource.requireUid(this);
    return _expensesCollection(uid).doc(expense.id).update({
      'amountMinor': expense.amountMinor,
      'currency': expense.currency,
      'category': expense.categoryId,
      'spentAt': Timestamp.fromDate(expense.spentAt),
      'note': expense.note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String id) {
    final uid = uidSource.requireUid(this);
    return _expensesCollection(uid).doc(id).delete();
  }

  CollectionReference<Map<String, dynamic>> _expensesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('expenses');

  Expense _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final spentAt = data['spentAt'];
    final category = data['category'];
    final note = data['note'];
    return Expense(
      id: doc.id,
      amountMinor: data['amountMinor'] as int? ?? 0,
      currency: data['currency'] as String? ?? '',
      categoryId: category is String ? category : 'other',
      spentAt: spentAt is Timestamp ? spentAt.toDate() : DateTime.now(),
      note: note is String ? note : null,
    );
  }
}
