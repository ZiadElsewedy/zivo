import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/auth_user.dart';

/// Firebase Auth's canonical provider ids. Reused verbatim as the `provider`
/// field on recorded events and account metadata, so the audit log speaks the
/// same vocabulary as the backend rather than a translation of it.
abstract final class AuthProviderIds {
  static const String password = 'password';
  static const String google = 'google.com';
  static const String apple = 'apple.com';
}

/// The one place a Firebase SDK `User` becomes the app's [AuthUser].
///
/// Isolated deliberately: this conversion is the seam where the auth vendor
/// stops and the app's own domain begins. Nothing above `data/` sees an
/// `fb.User`, so swapping the auth backend means rewriting this file and the
/// sources beside it — not the app.
AuthUser mapFirebaseUser(fb.User user) => AuthUser(
  uid: user.uid,
  email: user.email,
  displayName: user.displayName,
  isEmailVerified: user.emailVerified,
  providerIds: user.providerData
      .map((p) => p.providerId)
      .toList(growable: false),
  createdAt: user.metadata.creationTime,
  lastSignInAt: user.metadata.lastSignInTime,
);
