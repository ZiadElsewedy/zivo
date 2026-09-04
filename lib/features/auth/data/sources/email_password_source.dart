import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Everything the app does with an **email + password** credential against
/// Firebase Auth: create one, present one, re-present one, replace one.
///
/// This source deals only in credentials and Firebase SDK types. It returns
/// raw `fb.UserCredential` rather than the domain's `AuthResult`, because
/// deciding what a successful sign-in *means* (record it, map it, advance the
/// gate) is the repository's job, not a credential source's. Errors are the
/// exception: `fb.FirebaseAuthException` is translated at the boundary so no
/// SDK error type escapes `data/`.
class EmailPasswordSource {
  EmailPasswordSource(this._auth);

  final fb.FirebaseAuth _auth;

  /// Signs in with an existing credential.
  ///
  /// The client-side `PasswordPolicy` is deliberately NOT applied here:
  /// accounts may predate it, and the server is the trust boundary for
  /// sign-in anyway. Policy belongs on the paths that *set* a password.
  Future<fb.UserCredential> signIn({
    required String email,
    required String password,
  }) => _auth.signInWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );

  /// Creates the account, optionally seeding the provider-side display name.
  ///
  /// That name is a HINT for the profile the user is about to create — see
  /// `AuthUser.displayName`. It is written once, here, so a provider-populated
  /// name survives to prefill the profile form; nothing reads it as state.
  Future<fb.UserCredential> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      await cred.user!.updateDisplayName(name);
      await cred.user!.reload();
    }
    return cred;
  }

  /// Re-presents the current password. Firebase requires a recent login before
  /// any account-altering operation, and this is also what rejects a wrong
  /// current password on the change-password screen.
  ///
  /// It is additionally what mints a fresh `auth_time` in the ID token — which
  /// is what the server's `requireRecentAuth` check reads before it will
  /// delete an account. The reauthentication is therefore not a UX
  /// formality: it is the credential half of a server-enforced gate.
  Future<void> reauthenticate({
    required fb.User user,
    required String password,
  }) {
    final cred = fb.EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    return user.reauthenticateWithCredential(cred);
  }

  /// Sets a new password on an already-reauthenticated session.
  ///
  /// Note this is the CLIENT SDK path, which revokes other sessions on its
  /// own. The Admin SDK path used by the signed-out reset flow does not, which
  /// is why `functions/index.js` calls `revokeRefreshTokens` explicitly there.
  Future<void> updatePassword(fb.User user, String newPassword) =>
      user.updatePassword(newPassword);

  /// Whether [user] has a password credential at all — false for a
  /// Google/Apple-only account, which has no password to re-present.
  static bool hasPasswordProvider(fb.User user) =>
      user.providerData.any((p) => p.providerId == 'password');
}
