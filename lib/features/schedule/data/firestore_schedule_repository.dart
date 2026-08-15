import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/schedule_event.dart';
import '../domain/schedule_repository.dart';

/// The real [ScheduleRepository], backed by Firestore's `users/{uid}/schedule`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [ScheduleEvent] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
class FirestoreScheduleRepository implements ScheduleRepository {
  FirestoreScheduleRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<ScheduleEvent> _current = const [];
  StreamController<List<ScheduleEvent>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<ScheduleEvent> get current => List.unmodifiable(_current);

  @override
  Stream<List<ScheduleEvent>> watchAll() {
    return (_controller ??= StreamController<List<ScheduleEvent>>.broadcast(
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
    _querySub = _scheduleCollection(uid)
        .orderBy('start', descending: false)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        });
  }

  void _emit(List<ScheduleEvent> events) {
    _current = events;
    _controller?.add(current);
  }

  @override
  Future<void> add(ScheduleEvent event) {
    final uid = _requireUid();
    return _scheduleCollection(uid).doc(event.id).set({
      'title': event.title,
      'start': Timestamp.fromDate(event.start),
      'end': event.end == null ? null : Timestamp.fromDate(event.end!),
      'location': event.location,
      'label': event.label,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(ScheduleEvent event) {
    final uid = _requireUid();
    return _scheduleCollection(uid).doc(event.id).update({
      'title': event.title,
      'start': Timestamp.fromDate(event.start),
      'end': event.end == null ? null : Timestamp.fromDate(event.end!),
      'location': event.location,
      'label': event.label,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String id) {
    final uid = _requireUid();
    return _scheduleCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreScheduleRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _scheduleCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('schedule');

  ScheduleEvent _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final start = data['start'];
    final end = data['end'];
    final location = data['location'];
    final label = data['label'];
    return ScheduleEvent(
      id: doc.id,
      title: data['title'] as String? ?? '',
      start: start is Timestamp ? start.toDate() : DateTime.now(),
      end: end is Timestamp ? end.toDate() : null,
      location: location is String ? location : null,
      label: label is String ? label : null,
    );
  }
}
