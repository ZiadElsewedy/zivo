import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../auth_config.dart';

/// The identity-provider flows: Google and Apple.
///
/// Both providers answer the same two questions, and this source exists to
/// give them one shape:
///
///   1. **Sign in** — run the native flow and exchange its token for a
///      Firebase credential.
///   2. **Mint a fresh credential** — run the same flow purely to prove the
///      person is still there, for reauthentication before a destructive
///      operation. Federated accounts have no password to retype, so
///      re-running the provider sheet IS the reauthentication.
///
/// Those two used to be four near-identical inlined blocks in the repository.
/// Unifying them matters beyond tidiness: the credential-minting path is what
/// refreshes `auth_time` in the ID token, which is what the server checks
/// before deleting an account. A drift between "how we sign in" and "how we
/// re-prove" would be a security bug, so they share one implementation each.
///
/// Provider-specific exceptions are deliberately NOT caught here — the
/// repository maps them, because "the user tapped cancel" is a different
/// outcome from "the flow failed" and only the caller knows which of its own
/// result types to express that in.
class FederatedAuthSource {
  FederatedAuthSource({GoogleSignIn? googleSignIn})
    : _google = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _google;

  /// `google_sign_in` must be initialised exactly once before use; the future
  /// is cached so concurrent callers share the single initialisation.
  Future<void>? _googleInit;

  Future<void> _ensureGoogleInit() {
    return _googleInit ??= _google.initialize(
      serverClientId: AuthConfig.googleServerClientId.isEmpty
          ? null
          : AuthConfig.googleServerClientId,
    );
  }

  /// Whether Google sign-in can run on this device at all.
  Future<bool> get googleAvailable async {
    await _ensureGoogleInit();
    return _google.supportsAuthenticate();
  }

  /// Runs the Google flow and returns a Firebase credential, or null when the
  /// provider yields no id token (a misconfiguration, not a user action).
  Future<fb.AuthCredential?> googleCredential() async {
    await _ensureGoogleInit();
    if (!_google.supportsAuthenticate()) return null;
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) return null;
    return fb.GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Runs the Apple flow and returns a Firebase credential, plus the full name
  /// Apple discloses **only on the very first authorization** — after that it
  /// returns nulls forever, so the one chance to capture it is here.
  Future<({fb.AuthCredential credential, String fullName})>
  appleCredential() async {
    // A nonce binds this authorization to this request: Apple signs the hash
    // we send, and Firebase verifies the raw value matches, so an intercepted
    // identity token can't be replayed into a different sign-in.
    final rawNonce = _generateNonce();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256(rawNonce),
    );
    final credential = fb.OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
    );
    final fullName = [apple.givenName, apple.familyName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    return (credential: credential, fullName: fullName);
  }

  /// Whether an Apple credential actually carried an identity token. Apple can
  /// complete the sheet without one when the provider is misconfigured.
  static bool hasAppleIdentityToken(fb.AuthCredential credential) =>
      credential is fb.OAuthCredential && credential.idToken != null;

  /// Signs out of Google so the account picker reappears next time. Harmless
  /// (and ignored) if the user never signed in with Google.
  Future<void> signOutGoogle() async {
    await _ensureGoogleInit();
    await _google.signOut();
  }

  /// Revokes the app's Google authorization entirely — used on account
  /// deletion, where merely signing out would leave the grant standing.
  Future<void> disconnectGoogle() => _google.signOut();

  String _generateNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    // `Random.secure()`, not `Random()`: a predictable nonce defeats the
    // replay protection it exists to provide.
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();
}
