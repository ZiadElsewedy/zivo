import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/category_repository.dart';
import '../domain/expense_category.dart';

/// The real [CategoryRepository], backed by Firestore's
/// `users/{uid}/expenseCategories` subcollection. See
/// `FirestoreExpenseRepository` for the uid-rescoping pattern this mirrors.
class FirestoreCategoryRepository implements CategoryRepository {
  FirestoreCategoryRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<ExpenseCategory> _current = const [];
  bool _hasSnapshot = false;
  StreamController<List<ExpenseCategory>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<ExpenseCategory> get current => List.unmodifiable(_current);

  @override
  Stream<List<ExpenseCategory>> watchAll() async* {
    _controller ??= StreamController<List<ExpenseCategory>>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
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
    _querySub = _categoriesCollection(uid)
        .orderBy('createdAt')
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<ExpenseCategory> categories) {
    _current = categories;
    _hasSnapshot = true;
    _controller?.add(current);
  }

  @override
  Future<void> add(ExpenseCategory category) {
    final uid = _requireUid();
    return _categoriesCollection(uid).doc(category.id).set({
      'label': category.label,
      // The stable enum name, never a glyph — see [CategoryIcon]. Documents
      // written before this change carry `emoji` instead and are read through
      // the legacy path in [_fromDoc]; nothing writes `emoji` any more.
      'iconId': category.icon.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreCategoryRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _categoriesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('expenseCategories');

  ExpenseCategory _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final label = data['label'];
    return ExpenseCategory(
      id: doc.id,
      label: label is String ? label : 'Category',
      // Documents written before categories lost their colour still carry a
      // `hue` field. It is read by nothing and validated by nothing, so it
      // just sits there harmlessly until the doc is next rewritten.
      //
      // Prefer the current field; fall back to interpreting a pre-migration
      // `emoji` so categories saved before the switch keep their mark instead
      // of all collapsing onto the neutral one.
      icon: data.containsKey('iconId')
          ? categoryIconFromName(data['iconId'])
          : categoryIconFromLegacyEmoji(data['emoji']),
    );
  }
}
