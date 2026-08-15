import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/note.dart';
import '../domain/note_repository.dart';

/// The real [NoteRepository], backed by Firestore's `users/{uid}/notes`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Note] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
///
/// Unlike the Tasks/Expenses/Schedule repositories, `updatedAt` here is a
/// domain field owned by the entity (the note's own last-edit time), not
/// pure server metadata — it is written and read back verbatim rather than
/// stamped with `serverTimestamp()`.
class FirestoreNoteRepository implements NoteRepository {
  FirestoreNoteRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Note> _current = const [];
  StreamController<List<Note>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<Note> get current => List.unmodifiable(_current);

  @override
  Stream<List<Note>> watchAll() {
    return (_controller ??= StreamController<List<Note>>.broadcast(
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
    _querySub = _notesCollection(uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        });
  }

  void _emit(List<Note> notes) {
    _current = notes;
    _controller?.add(current);
  }

  @override
  Future<void> add(Note note) {
    final uid = _requireUid();
    return _notesCollection(uid).doc(note.id).set({
      'body': note.body,
      'title': note.title,
      'updatedAt': Timestamp.fromDate(note.updatedAt),
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreNoteRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _notesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('notes');

  Note _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final updatedAt = data['updatedAt'];
    final title = data['title'];
    return Note(
      id: doc.id,
      body: data['body'] as String? ?? '',
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
      title: title is String ? title : null,
    );
  }
}
