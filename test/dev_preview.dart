// THROWAWAY preview entrypoint — for a UI/UX visual walkthrough only.
// Boots ZIVO straight into the signed-in shell with fake auth + a complete
// profile and in-memory (empty) feature data, so we can see the real
// first-run Today / Hub / Ask / You without a backend or credentials.
//
// Run with:
//   flutter run -t test/dev_preview.dart --dart-define=USE_FIRESTORE=false -d <sim>
//
// Delete when the walkthrough is done. Not part of the app or the test suite.
import 'package:flutter/material.dart';
import 'package:zivo/app/app.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  const user = AuthUser(
    uid: 'fake-uid',
    email: 'you@zivo.app',
    displayName: 'Ziad',
    isEmailVerified: true,
    providerIds: <String>['google.com'],
  );
  final auth = FakeAuthRepository(initial: const Authenticated(user));
  runApp(ZivoApp(auth: auth, profiles: FakeProfileRepository()));
}
