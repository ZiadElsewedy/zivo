import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../domain/auth_activity_repository.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_result.dart';
import '../domain/auth_state.dart';
import '../domain/auth_user.dart';
import '../domain/otp_result.dart';
import 'auth_activity_recorder.dart';
import 'mappers/firebase_user_mapper.dart';
import 'sources/auth_callables_source.dart';
import 'sources/email_password_source.dart';
import 'sources/federated_auth_source.dart';

/// The real [AuthRepository] — a **composition root**, not an implementation.
///
/// Every mechanism lives in a source beside this file, each with one reason to
/// change:
///
/// | Concern | Lives in |
/// |---|---|
/// | Email + password credentials | `sources/email_password_source.dart` |
/// | Google + Apple flows, nonce, reauth credentials | `sources/federated_auth_source.dart` |
/// | Backend calls (OTP, deletion) | `sources/auth_callables_source.dart` |
/// | Firebase `User` → [AuthUser] | `mappers/firebase_user_mapper.dart` |
/// | Server rejection → OTP result | `mappers/otp_error_mapper.dart` |
/// | Audit/telemetry writes | `auth_activity_recorder.dart` |
///
/// What is left here is the part that genuinely belongs to the repository:
/// **orchestration and outcome-shaping.** Which order the steps run in, what
/// counts as cancellation versus failure, and when a session must be
/// refreshed. Those are decisions; the rest is machinery.
///
/// This is also the only file in the app allowed to hold FirebaseAuth,
/// google_sign_in, sign_in_with_apple and cloud_functions types at once —
/// together with its sources it is the entire surface that would be rewritten
/// to move to a different auth backend.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    FirebaseFunctions? functions,
    AuthActivityRepository? activityRepository,
  }) : _auth = firebaseAuth ?? fb.FirebaseAuth.instance,
       _federated = FederatedAuthSource(googleSignIn: googleSignIn),
       _callables = AuthCallablesSource(functions: functions),
       _activity = AuthActivityRecorder(activityRepository) {
    _passwords = EmailPasswordSource(_auth);
  }

  final fb.FirebaseAuth _auth;
  final FederatedAuthSource _federated;
  final AuthCallablesSource _callables;
  final AuthActivityRecorder _activity;
  late final EmailPasswordSource _passwords;

  // --- session ---------------------------------------------------------------

  @override
  Stream<AuthState> watchAuthState() async* {
    // Splash while the SDK restores any persisted session, then real state.
    yield const AuthUnknown();
    // `userChanges`, not `authStateChanges`: a server-side `emailVerified`
    // flip (observed after the forced token refresh in [verifyEmailOtp]) is a
    // change to the *user*, not to whether one is signed in — only
    // `userChanges` re-emits for it, and without that the gate would sit on
    // the verification screen after a successful verification.
    yield* _auth.userChanges().map<AuthState>(
      (user) => resolveAuthState(user == null ? null : mapFirebaseUser(user)),
    );
  }

  @override
  AuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : mapFirebaseUser(user);
  }

  @override
  Future<void> signOut() async {
    // Record the end before the identity is gone — the write needs a uid.
    final uid = _auth.currentUser?.uid;
    if (uid != null) _activity.signOut(uid);
    try {
      await _federated.signOutGoogle();
    } catch (_) {
      // Non-fatal: the Firebase sign-out below is the gate's source of truth.
    }
    await _auth.signOut();
  }

  // --- email + password ------------------------------------------------------

  @override
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _passwords.signIn(email: email, password: password);
    _activity.session(cred, provider: AuthProviderIds.password);
    return AuthSuccess(mapFirebaseUser(cred.user!));
  });

  @override
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) => _guard(() async {
    final cred = await _passwords.signUp(
      email: email,
      password: password,
      displayName: displayName,
    );
    _activity.accountCreated(cred, provider: AuthProviderIds.password);
    // Re-read from `currentUser`: `signUp` may have written a display name
    // after the credential was minted, so the credential's own snapshot is
    // already stale.
    return AuthSuccess(mapFirebaseUser(_auth.currentUser ?? cred.user!));
  });

  // --- federated providers ---------------------------------------------------

  @override
  Future<AuthResult> signInWithGoogle() => _guardProvider(() async {
    final credential = await _federated.googleCredential();
    if (credential == null) {
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.providerConfig,
          'Google sign-in is not available on this device.',
        ),
      );
    }
    final cred = await _auth.signInWithCredential(credential);
    _activity.federatedSession(cred);
    return AuthSuccess(mapFirebaseUser(cred.user!));
  });

  @override
  Future<AuthResult> signInWithApple() => _guardProvider(() async {
    final (:credential, :fullName) = await _federated.appleCredential();
    if (!FederatedAuthSource.hasAppleIdentityToken(credential)) {
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.providerConfig,
          'Apple sign-in did not return a valid token.',
        ),
      );
    }
    final cred = await _auth.signInWithCredential(credential);
    // Apple discloses the name ONLY on the first authorization and returns
    // nulls forever after, so persist it to the provider record the one time
    // it is offered — it is what prefills the profile form a moment later.
    final user = cred.user;
    if (user != null &&
        (user.displayName == null || user.displayName!.isEmpty) &&
        fullName.isNotEmpty) {
      await user.updateDisplayName(fullName);
      await user.reload();
    }
    _activity.federatedSession(cred);
    return AuthSuccess(mapFirebaseUser(_auth.currentUser ?? user!));
  });

  // --- email verification ----------------------------------------------------

  @override
  Future<OtpSendResult> sendEmailOtp() async {
    final result = await _callables.sendEmailOtp();
    // A stale client sitting on the verify screen after the flag flipped
    // elsewhere: refresh so `userChanges` advances the gate on its own.
    if (result is OtpSendAlreadyVerified) await _refreshSession();
    return result;
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtp(String code) async {
    final result = await _callables.verifyEmailOtp(code);
    // Verified server-side. The token still says otherwise until it is
    // refreshed — and that token is what the Firestore rules read, so this
    // refresh is what actually grants write access, not just what advances
    // the screen.
    if (result is OtpVerifySuccess) await _refreshSession();
    return result;
  }

  // --- password management ---------------------------------------------------

  @override
  Future<OtpSendResult> sendPasswordResetOtp({required String email}) =>
      _callables.sendPasswordResetOtp(email);

  @override
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  }) {
    // Deliberately no sign-in on success. Resetting a password sets the
    // credential; it does not open a session. Proving you can receive mail at
    // an address is a weaker claim than knowing the password, so the new
    // password earns its first session through the normal sign-in — which
    // also means the user types it once before relying on it.
    return _callables.resetPasswordWithOtp(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }

  @override
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _guard(() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return _expiredSession;
    // Reauthentication is both the freshness proof Firebase demands and the
    // check that rejects a wrong current password.
    await _passwords.reauthenticate(user: user, password: currentPassword);
    await _passwords.updatePassword(user, newPassword);
    _activity.passwordChanged(user.uid);
    return AuthSuccess(mapFirebaseUser(user));
  });

  // --- account lifecycle -----------------------------------------------------

  @override
  Future<AuthResult> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) return _expiredSession;

    return _guardProvider(() async {
      // 1) Reauthenticate. This is not a courtesy prompt: it mints a fresh
      //    `auth_time` in the ID token, and the server refuses to delete
      //    without one that is minutes old. Skipping it here does not skip
      //    the gate — it just produces a server-side rejection instead.
      final reauth = await _reauthenticate(user, password);
      if (reauth != null) return reauth;

      // 2) Erase data first, then the identity — server-side, in that order,
      //    so a partial failure can never orphan documents beneath a uid that
      //    no longer exists.
      await _callables.deleteAccount();

      // 3) Local cleanup so the picker reappears and the gate returns to
      //    sign-in on the now-null session.
      try {
        await _federated.disconnectGoogle();
      } catch (_) {
        // Non-fatal.
      }
      await _auth.signOut();
      return AuthSuccess(mapFirebaseUser(user));
    });
  }

  /// Re-proves the person behind [user], by whichever means their account
  /// actually has. Returns null on success, or the failure to surface.
  ///
  /// Password accounts retype the password; federated accounts re-run the
  /// provider sheet, because that IS their credential. An account with
  /// neither (which should not exist) falls through unchallenged rather than
  /// being made undeletable — the server's freshness check still applies.
  Future<AuthResult?> _reauthenticate(fb.User user, String? password) async {
    final providers = user.providerData.map((p) => p.providerId).toSet();

    if (providers.contains(AuthProviderIds.password)) {
      if (password == null || password.isEmpty || user.email == null) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.wrongPassword,
            'Enter your password to confirm.',
          ),
        );
      }
      await _passwords.reauthenticate(user: user, password: password);
      return null;
    }

    if (providers.contains(AuthProviderIds.google)) {
      final credential = await _federated.googleCredential();
      if (credential == null) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Google sign-in is not available on this device.',
          ),
        );
      }
      await user.reauthenticateWithCredential(credential);
      return null;
    }

    if (providers.contains(AuthProviderIds.apple)) {
      final (:credential, fullName: _) = await _federated.appleCredential();
      await user.reauthenticateWithCredential(credential);
      return null;
    }

    return null;
  }

  // --- shared plumbing -------------------------------------------------------

  /// Pulls the session's server-side truth back to this device and forces a
  /// new ID token.
  ///
  /// Both halves matter and neither is optional. `reload()` refreshes the
  /// local `User`, which is what `userChanges` re-emits from; `getIdToken(true)`
  /// mints a token carrying the new `email_verified` claim, which is what the
  /// Firestore rules gate writes on.
  Future<void> _refreshSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    await user.getIdToken(true);
  }

  /// Runs [action], translating Firebase's error codes into domain failures.
  /// For paths with no provider sheet, so no cancellation to distinguish.
  Future<AuthResult> _guard(Future<AuthResult> Function() action) async {
    try {
      return await action();
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } catch (_) {
      return _unknownFailure;
    }
  }

  /// [_guard] plus provider-sheet handling.
  ///
  /// The distinction this exists for: a user who dismisses the Google or Apple
  /// sheet has not hit an error, and must be shown nothing at all. Collapsing
  /// that into a failure produces a red banner every time someone changes
  /// their mind — which is why cancellation is its own result type rather
  /// than an error code.
  Future<AuthResult> _guardProvider(Future<AuthResult> Function() action) async {
    try {
      return await action();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.unknown,
          'Google sign-in failed. Please try again.',
        ),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.unknown,
          'Apple sign-in failed. Please try again.',
        ),
      );
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } on FirebaseFunctionsException catch (e) {
      // The server refused, not the SDK. The one case worth its own copy is a
      // stale credential proof: nothing the user typed was wrong, so telling
      // them to "try again" is right and "that was incorrect" is not.
      if (e.details is Map &&
          (e.details as Map)['reason'] == 'reauthRequired') {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.reauthRequired,
            'That took too long to confirm. Please try again.',
          ),
        );
      }
      return _unknownFailure;
    } catch (_) {
      return _unknownFailure;
    }
  }

  static const AuthResult _expiredSession = AuthFailed(
    AuthFailure(
      AuthFailureKind.providerConfig,
      'Your session expired. Please sign in again.',
    ),
  );

  static const AuthResult _unknownFailure = AuthFailed(
    AuthFailure(
      AuthFailureKind.unknown,
      'Something went wrong. Please try again.',
    ),
  );
}
