import 'auth_result.dart';
import 'auth_state.dart';
import 'auth_user.dart';
import 'otp_result.dart';

/// The seam between the app and whatever authentication backend it uses.
///
/// Presentation depends on these interfaces only — never on FirebaseAuth — so
/// the backend is a data-layer detail. The concrete implementation is
/// `FirebaseAuthRepository`; tests use `FakeAuthRepository`.
///
/// ## Why this is four interfaces and not one
///
/// The authentication surface is not one responsibility, it is four, and they
/// change for different reasons: sessions change when you add a provider,
/// verification changes when you change how you prove an address, password
/// management changes with your credential policy, and account lifecycle
/// changes with your data-retention obligations.
///
/// Naming them separately buys three things:
///
/// 1. **A screen depends on what it uses.** `VerifyEmailPage` needs
///    [EmailVerification] — five methods it will never call are not in its
///    field's type, so a reader can see the page's whole surface at a glance
///    and a test fake only has to implement what it exercises.
/// 2. **The groups are the documentation.** "Where does password reset live?"
///    is answered by a type name rather than by scrolling.
/// 3. **They compose into one object anyway.** [AuthRepository] is the union,
///    so DI still passes a single instance and nothing about wiring gets
///    harder. This is grouping without fragmentation.
///
/// A fifth responsibility — *recording* that authentication happened — is
/// deliberately NOT here. See `AuthActivityRepository`: bookkeeping must never
/// be able to fail a sign-in, which is a different contract, so it gets a
/// different interface.

/// **Sessions.** Who is signed in, how they got there, and how they leave.
abstract interface class SessionAuthentication {
  /// Emits the current [AuthState] and every subsequent change.
  ///
  /// Starts as [AuthUnknown] until the persisted session is restored, then
  /// resolves. Intended to back a single listener (the auth gate), so there
  /// are no duplicate subscriptions.
  Stream<AuthState> watchAuthState();

  /// The signed-in user right now, or null. Synchronous, for the launch path
  /// that needs an answer before the first frame rather than one stream tick
  /// later — without it, an already-signed-in user sees a splash flash.
  AuthUser? get currentUser;

  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  });

  /// Creates an account. [displayName] seeds the provider-side name, which is
  /// only ever a hint for the profile the user creates next — see
  /// [AuthUser.displayName].
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthResult> signInWithGoogle();

  Future<AuthResult> signInWithApple();

  /// Signs out of this app and of any linked provider session, so the account
  /// picker reappears next time rather than silently re-using the last one.
  Future<void> signOut();
}

/// **Email verification.** Proving the address on a password account is real.
///
/// Both methods are thin: every decision — code generation, hashing, expiry,
/// attempt caps, throttling — is server-side. The client names the call and
/// renders the verdict, because a client that could decide any of those could
/// bypass all of them.
abstract interface class EmailVerification {
  /// Requests a fresh code for the signed-in (but unverified) user.
  ///
  /// Safe to call on entering the verify screen: if a valid code was just
  /// sent, the backend reports a cooldown instead of sending again.
  Future<OtpSendResult> sendEmailOtp();

  /// Submits [code]. On success the backend marks the address verified and
  /// the implementation refreshes the session — which both advances the gate
  /// and mints the token claim the Firestore rules gate writes on.
  Future<OtpVerifyResult> verifyEmailOtp(String code);
}

/// **Password management.** Setting a credential, with and without a session.
abstract interface class PasswordManagement {
  /// Requests a reset code for [email] — for a **signed-out** user who has
  /// forgotten their password.
  ///
  /// The backend returns the same result whether or not [email] has an
  /// account, so this endpoint can't be used to discover who has one. Callers
  /// must therefore always advance to the code step on success; branching on
  /// existence here would rebuild the oracle the server withholds.
  Future<OtpSendResult> sendPasswordResetOtp({required String email});

  /// Verifies [code] for [email] and sets [newPassword] server-side.
  ///
  /// **The user is left signed out.** A reset sets a credential; it does not
  /// open a session. [newPassword] should already satisfy `PasswordPolicy`;
  /// the backend enforces it again as the trust boundary.
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Changes the **signed-in** user's password, reauthenticating with
  /// [currentPassword] first. Fails with [AuthFailureKind.wrongPassword] when
  /// that password is wrong. Only valid for accounts with a password provider.
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// **Account lifecycle.** The operations that end an account.
abstract interface class AccountLifecycle {
  /// Permanently deletes the signed-in account: all stored data, then the
  /// identity.
  ///
  /// Reauthenticates first — with [password] for password accounts, or by
  /// re-running the provider flow for Google/Apple. That step is not a
  /// courtesy prompt: it refreshes the ID token's `auth_time`, and the server
  /// refuses to delete without a fresh one. Returns [AuthCancelled] if the
  /// user backs out of a provider sheet.
  Future<AuthResult> deleteAccount({String? password});
}

/// The full authentication surface: every facet above, as one injectable
/// object. Depend on this when you genuinely span responsibilities (the app's
/// composition root, the settings screen); depend on a single facet when you
/// don't.
abstract interface class AuthRepository
    implements
        SessionAuthentication,
        EmailVerification,
        PasswordManagement,
        AccountLifecycle {}
