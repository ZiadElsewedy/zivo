import 'auth_result.dart';
import 'auth_state.dart';
import 'auth_user.dart';

/// The seam between the app and whatever authentication backend it uses.
///
/// Presentation depends only on this interface — never on FirebaseAuth — so the
/// backend is a data-layer detail (mirrors the repository convention used by
/// every other feature). The concrete implementation is
/// `FirebaseAuthRepository`; tests use `FakeAuthRepository`.
abstract interface class AuthRepository {
  /// Emits the current [AuthState] and every subsequent change. Starts as
  /// [AuthUnknown] until the persisted session (if any) is restored, then
  /// [Authenticated] / [Unauthenticated]. Intended to back a single listener
  /// (the auth gate) so there are no duplicate subscriptions.
  Stream<AuthState> watchAuthState();

  /// The signed-in user right now, or null. Synchronous convenience for call
  /// sites that already know they need the id (e.g. future Firestore writes).
  AuthUser? get currentUser;

  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthResult> signInWithGoogle();

  Future<AuthResult> signInWithApple();

  /// Signs the user out of this app (and any linked provider session so the
  /// account picker reappears next time).
  Future<void> signOut();
}
