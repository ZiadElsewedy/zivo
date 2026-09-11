import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/active_session.dart';
import '../domain/device_session_repository.dart';

/// Firestore-backed [DeviceSessionRepository]. The account's active session is
/// the single document `users/{uid}/session/current`; activating is a plain
/// `set` (no merge) so it wholly replaces the previous device's record, and
/// watching is a snapshot listener so a takeover reaches the losing device in
/// real time. Rules pin this doc to the owner and its shape — see
/// `firestore.rules` (`users/{userId}/session/{docId}`).
class FirestoreDeviceSessionRepository implements DeviceSessionRepository {
  FirestoreDeviceSessionRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _docId = 'current';

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('users').doc(uid).collection('session').doc(_docId);

  @override
  Future<void> activate(String uid, ActiveSession session) {
    return _ref(uid).set({
      'sessionId': session.sessionId,
      'deviceId': session.deviceId,
      'platform': session.platform,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<ActiveSession?> watch(String uid) =>
      _ref(uid).snapshots().map(_fromSnap);

  ActiveSession? _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return null;
    final sessionId = data['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    return ActiveSession(
      sessionId: sessionId,
      deviceId: data['deviceId'] is String ? data['deviceId'] as String : '',
      platform: data['platform'] is String ? data['platform'] as String : '',
    );
  }
}
