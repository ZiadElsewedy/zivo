import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/university_item.dart';
import '../domain/university_item_type.dart';
import '../domain/university_repository.dart';

/// The real [UniversityRepository], backed by Firestore's
/// `users/{uid}/universityItems` subcollection. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [UniversityItem] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
///
/// The Firestore query is ordered by `createdAt` (which every doc has) rather
/// than `orderBy('due')`, because Firestore excludes documents missing the
/// order-by field from the result set — an `orderBy('due')` query would
/// silently drop undated items. Instead, ordering by due-date (soonest first,
/// undated last) is applied client-side in [_sorted].
class FirestoreUniversityRepository implements UniversityRepository {
  FirestoreUniversityRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<UniversityItem> _current = const [];
  StreamController<List<UniversityItem>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<UniversityItem> get current => List.unmodifiable(_current);

  @override
  Stream<List<UniversityItem>> watchAll() {
    return (_controller ??= StreamController<List<UniversityItem>>.broadcast(
      onListen: _start,
      onCancel: _stop,
    )).stream;
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
    _querySub = _universityCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(_sorted(snapshot.docs.map(_fromDoc).toList(growable: false)));
        });
  }

  /// Soonest due date first; undated items last.
  List<UniversityItem> _sorted(List<UniversityItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final aDue = a.due;
      final bDue = b.due;
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return sorted;
  }

  void _emit(List<UniversityItem> items) {
    _current = items;
    _controller?.add(current);
  }

  @override
  Future<void> add(UniversityItem item) {
    final uid = _requireUid();
    return _universityCollection(uid).doc(item.id).set({
      'title': item.title,
      'type': item.type.name,
      'createdAt': Timestamp.fromDate(item.createdAt),
      'due': item.due == null ? null : Timestamp.fromDate(item.due!),
      'courseName': item.courseName,
      'done': item.done,
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setDone(String id, bool done) {
    final uid = _requireUid();
    return _universityCollection(
      uid,
    ).doc(id).update({'done': done, 'updatedAt': FieldValue.serverTimestamp()});
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreUniversityRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _universityCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('universityItems');

  UniversityItem _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final due = data['due'];
    final rawType = data['type'] as String?;
    return UniversityItem(
      id: doc.id,
      title: data['title'] as String? ?? '',
      type: UniversityItemType.values.firstWhere(
        (t) => t.name == rawType,
        orElse: () => UniversityItemType.assignment,
      ),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      due: due is Timestamp ? due.toDate() : null,
      courseName: data['courseName'] as String?,
      done: data['done'] as bool? ?? false,
    );
  }
}
