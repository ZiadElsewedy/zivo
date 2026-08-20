import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/uid_source.dart';
import '../domain/media_storage_preferences.dart';

/// The real [MediaPreferencesRepository], backed by a single Firestore document
/// per account at `users/{uid}/settings/media`. A subdocument (rather than
/// fields on the profile doc) keeps media/storage concerns self-contained.
///
/// Like the feature repositories, it is constructed once at app root without a
/// uid and resolves the signed-in user via [UidSource], re-scoping [watch] as
/// the uid changes (emitting defaults when signed out).
class FirestoreMediaPreferencesRepository implements MediaPreferencesRepository {
  FirestoreMediaPreferencesRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid).collection('settings').doc('media');

  @override
  Stream<MediaStoragePreferences> watch() {
    late StreamController<MediaStoragePreferences> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? docSub;

    void listenForUid(String? uid) {
      docSub?.cancel();
      if (uid == null) {
        controller.add(MediaStoragePreferences.defaults);
        return;
      }
      docSub = _doc(uid).snapshots().listen(
            (snap) => controller.add(_fromSnap(snap)),
            onError: controller.addError,
          );
    }

    controller = StreamController<MediaStoragePreferences>.broadcast(
      onListen: () {
        listenForUid(uidSource.currentUid());
        uidSub = uidSource.uidChanges.listen(listenForUid);
      },
      onCancel: () {
        uidSub?.cancel();
        docSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<MediaStoragePreferences> read() async {
    final uid = uidSource.currentUid();
    if (uid == null) return MediaStoragePreferences.defaults;
    return _fromSnap(await _doc(uid).get());
  }

  @override
  Future<void> save(MediaStoragePreferences preferences) async {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreMediaPreferencesRepository: no signed-in user.');
    }
    await _doc(uid).set({
      'saveToPhotos': preferences.saveToPhotos,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  MediaStoragePreferences _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return MediaStoragePreferences.defaults;
    return MediaStoragePreferences(
      saveToPhotos: data['saveToPhotos'] as bool? ?? false,
    );
  }
}
