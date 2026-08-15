import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

/// The real [ProfileRepository], backed by Firestore's `users/{uid}`
/// collection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [UserProfile] model.
class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Stream<UserProfile?> watchProfile(String uid) =>
      _users.doc(uid).snapshots().map(_fromSnap);

  @override
  Future<UserProfile?> fetchProfile(String uid) async {
    final snap = await _users.doc(uid).get();
    return _fromSnap(snap);
  }

  @override
  Future<void> saveProfile({
    required String uid,
    required String name,
    required DateTime dateOfBirth,
  }) {
    return _users.doc(uid).set({
      'name': name,
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  UserProfile? _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final name = data['name'];
    final dateOfBirth = data['dateOfBirth'];
    if (name is! String || name.isEmpty) return null;
    if (dateOfBirth is! Timestamp) return null;
    return UserProfile(
      uid: snap.id,
      name: name,
      dateOfBirth: dateOfBirth.toDate(),
    );
  }
}
