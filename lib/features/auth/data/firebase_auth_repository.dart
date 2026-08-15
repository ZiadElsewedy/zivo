import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_result.dart';
import '../domain/auth_state.dart';
import '../domain/auth_user.dart';
import 'auth_config.dart';

/// The real [AuthRepository], backed by Firebase Auth plus the Google and Apple
/// native sign-in flows. This is the *only* place FirebaseAuth / provider SDK
/// types are allowed — everything above consumes the domain models.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _auth = firebaseAuth ?? fb.FirebaseAuth.instance,
      _google = googleSignIn ?? GoogleSignIn.instance;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;

  /// google_sign_in must be initialised exactly once before use; cache the call.
  Future<void>? _googleInit;

  @override
  Stream<AuthState> watchAuthState() async* {
    // Splash while the SDK restores any persisted session, then real state.
    yield const AuthUnknown();
    yield* _auth.authStateChanges().map<AuthState>(
      (user) => user == null ? const Unauthenticated() : Authenticated(_map(user)),
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
  Future<void> signOut() async {
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
}
