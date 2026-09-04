import 'package:firebase_auth/firebase_auth.dart';

/// The signed-in user's uid, both synchronously and as a stream of changes.
///
/// Firestore-backed repositories are constructed once at app root (before
/// sign-in), so they can't take a `uid` constructor parameter. Instead they
/// depend on this tiny seam, which lets tests inject a plain `() => uid` +
/// `Stream<String?>` without mocking `FirebaseAuth`.
class UidSource {
  UidSource({required this.currentUid, required this.uidChanges});

  /// Builds a [UidSource] backed by the real Firebase Auth instance.
  factory UidSource.firebaseAuth({FirebaseAuth? auth}) {
    final firebaseAuth = auth ?? FirebaseAuth.instance;
    return UidSource(
      currentUid: () => firebaseAuth.currentUser?.uid,
      uidChanges: firebaseAuth
          .authStateChanges()
          .map((user) => user?.uid)
          .distinct(),
    );
  }

  /// The current uid, or null if signed out. Synchronous.
  final String? Function() currentUid;

  /// Emits whenever the signed-in uid changes (including sign-out as null).
  final Stream<String?> uidChanges;
}

/// The signed-in-user precondition every Firestore repository puts in front of
/// a write.
///
/// Reads are uid-scoped by `UidScopedMirror` and degrade to an empty value
/// when signed out; a *write* has nowhere to go, so it throws instead. Every
/// repository used to carry an identical private `_requireUid()` differing
/// only in the class name it reported — [owner] supplies that, so the message
/// is unchanged ("FirestoreMomentRepository: no signed-in user.").
extension RequireUid on UidSource {
  String requireUid(Object owner) {
    final uid = currentUid();
    if (uid == null) {
      throw StateError('${owner.runtimeType}: no signed-in user.');
    }
    return uid;
  }
}
