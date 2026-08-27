import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
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
import 'auth_config.dart';

/// The real [AuthRepository], backed by Firebase Auth plus the Google and Apple
/// native sign-in flows. This is the *only* place FirebaseAuth / provider SDK
/// types are allowed — everything above consumes the domain models.
///
/// Auth *bookkeeping* (the account-metadata summary + event log) rides along
/// via [activityRepository]: every successful authentication records itself
/// fire-and-forget, so telemetry can never delay or fail a sign-in. When no
/// repository is injected (tests, offline runs) nothing is recorded.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    FirebaseFunctions? functions,
    AuthActivityRepository? activityRepository,
  }) : _auth = firebaseAuth ?? fb.FirebaseAuth.instance,
       _google = googleSignIn ?? GoogleSignIn.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _activity = activityRepository;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;
  final FirebaseFunctions _functions;
  final AuthActivityRepository? _activity;

  /// google_sign_in must be initialised exactly once before use; cache the call.
  Future<void>? _googleInit;

  @override
  Stream<AuthState> watchAuthState() async* {
    // Splash while the SDK restores any persisted session, then real state.
    yield const AuthUnknown();
    // `userChanges` (not `authStateChanges`) so a server-side `emailVerified`
    // flip — observed after we force-refresh the token in [verifyEmailOtp] —
    // re-emits and advances the gate past AwaitingEmailVerification.
    yield* _auth.userChanges().map<AuthState>(
      (user) => resolveAuthState(user == null ? null : _map(user)),
    );
  }

  @override
  AuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _map(user);
  }

  @override
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _recordSession(cred, provider: kEmailProviderId);
      return AuthSuccess(_map(cred.user!));
    });
  }

  @override
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _guard(() async {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final name = displayName?.trim();
      if (name != null && name.isNotEmpty) {
        await cred.user!.updateDisplayName(name);
        await cred.user!.reload();
      }
      _recordAccountCreated(cred, provider: kEmailProviderId);
      return AuthSuccess(_map(_auth.currentUser ?? cred.user!));
    });
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      await _ensureGoogleInit();
      if (!_google.supportsAuthenticate()) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Google sign-in is not available on this device.',
          ),
        );
      }
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Google sign-in did not return a valid token.',
          ),
        );
      }
      final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await _auth.signInWithCredential(credential);
      _recordSessionByNewness(userCred);
      return AuthSuccess(_map(userCred.user!));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(AuthFailureKind.unknown, 'Google sign-in failed. Please try again.'),
      );
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } catch (_) {
      return _unknownFailure;
    }
  }

  @override
  Future<AuthResult> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );
      if (appleCredential.identityToken == null) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Apple sign-in did not return a valid token.',
          ),
        );
      }
      final oauthCredential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      final userCred = await _auth.signInWithCredential(oauthCredential);
      // Apple returns the name only on the *first* authorization; persist it
      // to the Firebase profile once so it survives.
      final fullName = [appleCredential.givenName, appleCredential.familyName]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
      final user = userCred.user;
      if (user != null &&
          (user.displayName == null || user.displayName!.isEmpty) &&
          fullName.isNotEmpty) {
        await user.updateDisplayName(fullName);
        await user.reload();
      }
      _recordSessionByNewness(userCred);
      return AuthSuccess(_map(_auth.currentUser ?? user!));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(AuthFailureKind.unknown, 'Apple sign-in failed. Please try again.'),
      );
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } catch (_) {
      return _unknownFailure;
    }
  }

  @override
  Future<OtpSendResult> sendEmailOtp() => _sendOtp('sendEmailOtp');

  @override
  Future<OtpSendResult> sendPasswordResetOtp({required String email}) =>
      _sendOtp('sendPasswordResetOtp', payload: {'email': email.trim()});

  /// Shared "request a code" call used by both the email-verification and
  /// password-reset flows. [payload] is null for the (authenticated)
  /// verification send and carries the email for the (signed-out) reset send.
  Future<OtpSendResult> _sendOtp(
    String callableName, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      final callable = _functions.httpsCallable(callableName);
      final res = payload == null
          ? await callable.call<Map<dynamic, dynamic>>()
          : await callable.call<Map<dynamic, dynamic>>(payload);
      final data = res.data;
      final status = data['status'] as String?;
      if (status == 'already-verified') {
        // A stale client on the verify screen: the flag flipped elsewhere.
        // Refresh the session so `userChanges` advances the gate on its own.
        final user = _auth.currentUser;
        if (user != null) {
          await user.reload();
          await user.getIdToken(true);
        }
        return const OtpSendAlreadyVerified();
      }
      if (status == 'cooldown') {
        return OtpSendCooldown(
          retryAfterSeconds: _asInt(data['retryAfterSeconds']) ?? 60,
        );
      }
      return OtpSendSuccess(
        cooldownSeconds: _asInt(data['cooldownSeconds']) ?? 60,
        expiresInSeconds: _asInt(data['expiresInSeconds']) ?? 600,
      );
    } on FirebaseFunctionsException catch (e) {
      return _mapOtpSendError(e);
    } catch (_) {
      return const OtpSendFailed(
        AuthFailure(
          AuthFailureKind.unknown,
          'Something went wrong. Please try again.',
        ),
      );
    }
  }

  OtpSendResult _mapOtpSendError(FirebaseFunctionsException e) {
    if (e.code == 'resource-exhausted') {
      return OtpSendFailed(
        const AuthFailure(
          AuthFailureKind.tooManyRequests,
          'Too many code requests. Please try again later.',
        ),
        retryAfterSeconds: _detailInt(e.details, 'retryAfterSeconds'),
      );
    }
    if (e.code == 'unauthenticated') {
      return const OtpSendFailed(
        AuthFailure(
          AuthFailureKind.providerConfig,
          'Your session expired. Please sign in again.',
        ),
      );
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      return const OtpSendFailed(
        AuthFailure(
          AuthFailureKind.networkError,
          "Couldn't send the code. Check your connection and try again.",
        ),
      );
    }
    return const OtpSendFailed(
      AuthFailure(
        AuthFailureKind.emailDeliveryFailed,
        "We couldn't send your code right now. Please try again in a moment.",
      ),
    );
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtp(String code) async {
    final result = await _verifyOtp('verifyEmailOtp', {'code': code});
    if (result is OtpVerifySuccess) {
      // Verified server-side. Reload + force a token refresh so `userChanges`
      // re-emits with emailVerified == true and the gate advances.
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        await user.getIdToken(true);
      }
    }
    return result;
  }

  @override
  Future<OtpVerifyResult> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    // Deliberately no sign-in on success: resetting a password sets the
    // credential, it does not start a session. Proving you can receive a code
    // at an address is a weaker claim than knowing the password, so the new
    // password is made to earn its first session through the normal sign-in
    // — which also means the user leaves the flow having typed the password
    // they just chose at least once.
    return _verifyOtp('resetPasswordWithOtp', {
      'email': email.trim(),
      'code': code,
      'newPassword': newPassword,
    });
  }

  /// Shared "submit a code" call used by both the email-verification and
  /// password-reset flows; maps every server rejection onto an
  /// [OtpVerifyResult]. Callers layer any success side-effect on top.
  Future<OtpVerifyResult> _verifyOtp(
    String callableName,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _functions
          .httpsCallable(callableName)
          .call<Map<dynamic, dynamic>>(payload);
      return const OtpVerifySuccess();
    } on FirebaseFunctionsException catch (e) {
      return _mapOtpVerifyError(e);
    } catch (_) {
      return const OtpVerifyFailed(
        AuthFailure(
          AuthFailureKind.unknown,
          'Something went wrong. Please try again.',
        ),
      );
    }
  }

  OtpVerifyResult _mapOtpVerifyError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
        // The reset flow tags a rejected-as-weak password so we don't mislabel
        // it as a wrong code.
        if (_detailString(e.details, 'reason') == 'weakPassword') {
          return const OtpVerifyFailed(
            AuthFailure(
              AuthFailureKind.weakPassword,
              'Choose a stronger password (at least 8 characters, with upper- '
                  'and lowercase letters and a number).',
            ),
          );
        }
        return OtpVerifyInvalid(
          attemptsRemaining: _detailInt(e.details, 'attemptsRemaining'),
        );
      case 'not-found':
      case 'failed-precondition':
        return const OtpVerifyExpired();
      case 'resource-exhausted':
        return OtpVerifyTooManyAttempts(
          retryAfterSeconds: _detailInt(e.details, 'retryAfterSeconds'),
        );
      case 'unauthenticated':
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Your session expired. Please sign in again.',
          ),
        );
      // A timeout is a connectivity problem, not an expired code — say so
      // rather than telling the user to request a fresh code.
      case 'deadline-exceeded':
      case 'unavailable':
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.networkError,
            "Couldn't verify the code. Check your connection and try again.",
          ),
        );
      default:
        return const OtpVerifyFailed(
          AuthFailure(
            AuthFailureKind.emailDeliveryFailed,
            "Couldn't verify your code right now. Please try again in a moment.",
          ),
        );
    }
  }

  @override
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _guard(() async {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        return const AuthFailed(
          AuthFailure(
            AuthFailureKind.providerConfig,
            'Your session expired. Please sign in again.',
          ),
        );
      }
      // Firebase requires a recent login to change a password: reauthenticate
      // with the current one first (this is also what rejects a wrong current
      // password), then set the new one.
      final cred = fb.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      _recordPasswordChanged(user.uid);
      return AuthSuccess(_map(user));
    });
  }

  @override
  Future<AuthResult> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.providerConfig,
          'Your session expired. Please sign in again.',
        ),
      );
    }
    final providers = user.providerData.map((p) => p.providerId).toSet();
    try {
      // 1) Reauthenticate — the deliberate-action gate before an irreversible
      //    delete (Firebase also requires a recent login for account changes).
      if (providers.contains(kEmailProviderId)) {
        if (password == null || password.isEmpty || user.email == null) {
          return const AuthFailed(
            AuthFailure(
              AuthFailureKind.wrongPassword,
              'Enter your password to confirm.',
            ),
          );
        }
        final cred = fb.EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(cred);
      } else if (providers.contains(kGoogleProviderId)) {
        final cred = await _obtainGoogleCredential();
        if (cred == null) {
          return const AuthFailed(
            AuthFailure(
              AuthFailureKind.providerConfig,
              'Google sign-in is not available on this device.',
            ),
          );
        }
        await user.reauthenticateWithCredential(cred);
      } else if (providers.contains(kAppleProviderId)) {
        final cred = await _obtainAppleCredential();
        await user.reauthenticateWithCredential(cred);
      }
      // 2) Erase all Firestore data + the auth identity server-side.
      await _functions
          .httpsCallable('deleteAccount')
          .call<Map<dynamic, dynamic>>();
      // 3) Local cleanup so the picker reappears and the gate returns to
      //    sign-in on the now-null session.
      try {
        await _ensureGoogleInit();
        await _google.signOut();
      } catch (_) {
        // Non-fatal.
      }
      await _auth.signOut();
      return AuthSuccess(_map(user));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(AuthFailureKind.unknown,
            'Google sign-in failed. Please try again.'),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthCancelled();
      }
      return const AuthFailed(
        AuthFailure(AuthFailureKind.unknown,
            'Apple sign-in failed. Please try again.'),
      );
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } catch (_) {
      return _unknownFailure;
    }
  }

  /// Builds a fresh Google credential by re-running the sign-in flow — used to
  /// reauthenticate before deleting a Google-backed account. Returns null when
  /// Google sign-in isn't available or yields no id token.
  Future<fb.AuthCredential?> _obtainGoogleCredential() async {
    await _ensureGoogleInit();
    if (!_google.supportsAuthenticate()) return null;
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) return null;
    return fb.GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Builds a fresh Apple credential by re-running the authorization — used to
  /// reauthenticate before deleting an Apple-backed account.
  Future<fb.AuthCredential> _obtainAppleCredential() async {
    final rawNonce = _generateNonce();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256(rawNonce),
    );
    return fb.OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );
  }

  @override
  Future<void> signOut() async {
    // Record the session end before the identity is gone — the write targets
    // `users/{uid}` explicitly, so it completes regardless of local state.
    final uid = _auth.currentUser?.uid;
    if (uid != null && _activity != null) {
      unawaited(_activity.recordSignOut(uid: uid));
    }
    // Sign out of Google as well so the account picker reappears next time.
    // Harmless (and ignored) if the user never signed in with Google.
    try {
      await _ensureGoogleInit();
      await _google.signOut();
    } catch (_) {
      // Non-fatal: Firebase sign-out below is the source of truth for the gate.
    }
    await _auth.signOut();
  }

  // --- auth activity bookkeeping -------------------------------------------

  /// Firebase Auth's canonical provider ids, reused verbatim as the
  /// `provider` field on recorded events and account metadata.
  static const String kEmailProviderId = 'password';
  static const String kGoogleProviderId = 'google.com';
  static const String kAppleProviderId = 'apple.com';

  /// Records a federated (Google/Apple) authentication, distinguishing an
  /// account's very first authentication from every later one via the SDK's
  /// server-side `isNewUser` flag — email sign-up paths know this statically,
  /// federated ones can only observe it here.
  void _recordSessionByNewness(fb.UserCredential cred) {
    final provider =
        cred.additionalUserInfo?.providerId ?? kGoogleProviderId;
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    if (isNew) {
      _recordAccountCreated(cred, provider: provider);
    } else {
      _recordSession(cred, provider: provider);
    }
  }

  /// Fire-and-forget registration bookkeeping. Never awaited and never throws:
  /// a lost telemetry write costs one gap in the log, not a failed sign-up.
  void _recordAccountCreated(fb.UserCredential cred,
      {required String provider}) {
    final uid = cred.user?.uid;
    final activity = _activity;
    if (uid == null || activity == null) return;
    unawaited(activity.recordAccountCreated(
      uid: uid,
      provider: provider,
      platform: currentPlatformName,
    ));
  }

  /// Fire-and-forget sign-in bookkeeping; carries Firebase's own trusted
  /// creation time so a summary doc missing `createdAt` (e.g. the
  /// registration-era write was lost offline) gets backfilled from truth.
  void _recordSession(fb.UserCredential cred, {required String provider}) {
    final user = cred.user;
    final activity = _activity;
    if (user == null || activity == null) return;
    unawaited(activity.recordSignIn(
      uid: user.uid,
      provider: provider,
      platform: currentPlatformName,
      fallbackCreatedAt: _parseAuthTime(user.metadata.creationTime),
    ));
  }

  /// Fire-and-forget password-change bookkeeping for the in-app change flow;
  /// never awaited and never throws (like every other recording call here).
  void _recordPasswordChanged(String uid) {
    final activity = _activity;
    if (activity == null) return;
    unawaited(activity.recordPasswordChanged(uid: uid));
  }

  /// The device label recorded with client-written events (`ios`, `android`,
  /// `macos`, `web`).
  static String get currentPlatformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// Firebase Auth exposes its trusted timestamps as `DateTime?`; kept as a
  /// named helper so the provenance reads clearly at call sites.
  static DateTime? _parseAuthTime(DateTime? time) => time;

  // --- helpers -------------------------------------------------------------

  Future<void> _ensureGoogleInit() {
    return _googleInit ??= _google.initialize(
      serverClientId: AuthConfig.googleServerClientId.isEmpty
          ? null
          : AuthConfig.googleServerClientId,
    );
  }

  AuthUser _map(fb.User user) => AuthUser(
    uid: user.uid,
    email: user.email,
    displayName: user.displayName,
    isEmailVerified: user.emailVerified,
    providerIds: user.providerData
        .map((p) => p.providerId)
        .toList(growable: false),
    createdAt: _parseAuthTime(user.metadata.creationTime),
    lastSignInAt: _parseAuthTime(user.metadata.lastSignInTime),
  );

  Future<AuthResult> _guard(Future<AuthResult> Function() run) async {
    try {
      return await run();
    } on fb.FirebaseAuthException catch (e) {
      return AuthFailed(mapAuthErrorCode(e.code));
    } catch (_) {
      return _unknownFailure;
    }
  }

  static const AuthResult _unknownFailure = AuthFailed(
    AuthFailure(AuthFailureKind.unknown, 'Something went wrong. Please try again.'),
  );

  String _generateNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Callable results are JSON-ish `Object?`; coerce a numeric field to int.
  static int? _asInt(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  /// Pulls a numeric field out of an [FirebaseFunctionsException.details] map.
  static int? _detailInt(Object? details, String key) =>
      details is Map ? _asInt(details[key]) : null;

  /// Pulls a string field out of an [FirebaseFunctionsException.details] map.
  static String? _detailString(Object? details, String key) =>
      details is Map && details[key] is String ? details[key] as String : null;
}
