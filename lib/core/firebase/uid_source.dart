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
