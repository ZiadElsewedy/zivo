import 'auth_result.dart';
import 'auth_state.dart';
import 'auth_user.dart';
import 'otp_result.dart';

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

  /// Requests a fresh 6-digit verification code be emailed to the currently
  /// signed-in (but unverified) email/password user. Safe to call on entering
  /// the verify screen: if a valid code was just sent, the backend reports a
  /// cooldown instead of sending again. All generation, hashing, expiry and
  /// rate-limiting happen server-side.
  Future<OtpSendResult> sendEmailOtp();

  /// Submits [code] for server-side verification. On success the backend marks
  /// the email verified and this refreshes the session so the auth stream
  /// advances past [AwaitingEmailVerification].
  Future<OtpVerifyResult> verifyEmailOtp(String code);

  /// Requests a 6-digit password-reset code be emailed to [email], for a
  /// **signed-out** user who has forgotten their password. To avoid revealing
  /// which addresses have accounts, the backend returns the same result
  /// whether or not [email] belongs to a password account — so the UI always
  /// advances to the code step on success. All rate-limiting mirrors
  /// [sendEmailOtp].
  Future<OtpSendResult> sendPasswordResetOtp({required String email});

  /// Verifies [code] for [email] and, on success, sets [newPassword]
  /// server-side and signs the user in with the new credentials (so the auth
  /// stream advances). [newPassword] should already satisfy the client
  /// [PasswordPolicy]; the backend enforces it again as the trust boundary.
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Changes the **signed-in** password user's password. Reauthenticates with
  /// [currentPassword] first (Firebase requires a recent login), then sets
  /// [newPassword]. Fails with [AuthFailureKind.wrongPassword] when the current
  /// password is wrong. Only valid for accounts with a `password` provider.
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Permanently deletes the signed-in account: reauthenticates first (with
  /// [password] for password accounts, or by re-running the provider flow for
  /// Google/Apple), then erases all Firestore data and the auth identity
  /// server-side, and signs out locally. Returns [AuthCancelled] if the user
  /// backs out of a provider reauth sheet.
  Future<AuthResult> deleteAccount({String? password});

  /// Signs the user out of this app (and any linked provider session so the
  /// account picker reappears next time).
  Future<void> signOut();
}
