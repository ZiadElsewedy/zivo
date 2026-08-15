import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';

/// The real [TaskRepository], backed by Firestore's `users/{uid}/tasks`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Task] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
class FirestoreTaskRepository implements TaskRepository {
  FirestoreTaskRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Task> _current = const [];
  StreamController<List<Task>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<Task> get current => List.unmodifiable(_current);

  @override
  Stream<List<Task>> watchAll() {
    return (_controller ??= StreamController<List<Task>>.broadcast(
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
    _querySub = _tasksCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        });
  }

  void _emit(List<Task> tasks) {
    _current = tasks;
    _controller?.add(current);
  }

  @override
  Future<void> add(Task task) {
    final uid = _requireUid();
    return _tasksCollection(uid).doc(task.id).set({
      'title': task.title,
      'createdAt': Timestamp.fromDate(task.createdAt),
      'due': task.due == null ? null : Timestamp.fromDate(task.due!),
      'priority': task.priority,
      'done': task.done,
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setDone(String id, bool done) {
    final uid = _requireUid();
    return _tasksCollection(
      uid,
    ).doc(id).update({'done': done, 'updatedAt': FieldValue.serverTimestamp()});
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreTaskRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _tasksCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('tasks');

  Task _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final due = data['due'];
    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      due: due is Timestamp ? due.toDate() : null,
      priority: data['priority'] as bool? ?? false,
      done: data['done'] as bool? ?? false,
    );
  }
}
