import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Expense> _current = const [];
  bool _hasSnapshot = false;
  StreamController<List<Expense>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<Expense> get current => List.unmodifiable(_current);

  @override
  Stream<List<Expense>> watchAll() async* {
    _controller ??= StreamController<List<Expense>>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    // A broadcast stream never replays its latest value to a *late* subscriber.
    // The Today dashboard subscribes first (it stays alive in the shell's
    // IndexedStack) and consumes the initial snapshot, so a Hub detail page
    // opened afterwards would otherwise sit on ConnectionState.waiting forever
    // whenever the collection is empty. Replay the cached snapshot on subscribe
    // so every listener sees the current value immediately — matching the
    // in-memory repo contract the pages and tests rely on.
    if (_hasSnapshot) yield current;
    yield* _controller!.stream;
  }

  void _start() {
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  void _stop() {
    _uidSub?.cancel();
    _uidSub = null;
    _querySub?.cancel();
    _querySub = null;
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onUidChanged(String? uid) {
    _querySub?.cancel();
    if (uid == null) {
      _emit(const []);
      return;
    }
    _querySub = _expensesCollection(uid)
        .orderBy('spentAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<Expense> expenses) {
    _current = expenses;
    _hasSnapshot = true;
    _controller?.add(current);
  }

  @override
  Future<void> add(Expense expense) {
    final uid = _requireUid();
    return _expensesCollection(uid).doc(expense.id).set({
      'amountMinor': expense.amountMinor,
      'currency': expense.currency,
      'category': expense.category.name,
      'spentAt': Timestamp.fromDate(expense.spentAt),
      'note': expense.note,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(Expense expense) {
    final uid = _requireUid();
    return _expensesCollection(uid).doc(expense.id).update({
      'amountMinor': expense.amountMinor,
      'currency': expense.currency,
      'category': expense.category.name,
      'spentAt': Timestamp.fromDate(expense.spentAt),
      'note': expense.note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String id) {
    final uid = _requireUid();
    return _expensesCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreExpenseRepository: no signed-in user.');
    }
    return uid;
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
      category: ExpenseCategory.values.firstWhere(
        (c) => c.name == category,
        orElse: () => ExpenseCategory.other,
      ),
      spentAt: spentAt is Timestamp ? spentAt.toDate() : DateTime.now(),
      note: note is String ? note : null,
    );
  }
}
