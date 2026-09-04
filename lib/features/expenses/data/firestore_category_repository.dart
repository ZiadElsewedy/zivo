import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<ExpenseCategory>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _categoriesCollection(uid)
          .orderBy('createdAt')
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<ExpenseCategory>> _mirror;

  @override
  List<ExpenseCategory> get current => List.unmodifiable(_mirror.current);

  @override
  Stream<List<ExpenseCategory>> watchAll() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> add(ExpenseCategory category) {
    final uid = uidSource.requireUid(this);
    return _categoriesCollection(uid).doc(category.id).set({
      'label': category.label,
      // The stable enum name, never a glyph — see [CategoryIcon]. Documents
      // written before this change carry `emoji` instead and are read through
      // the legacy path in [_fromDoc]; nothing writes `emoji` any more.
      'iconId': category.icon.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
