// TEMPORARY visual-audit entrypoint — NOT shipped, NOT a test.
//
// Boots the real ZivoApp already signed in (fake auth + fake profile) and with
// USE_FIRESTORE=false so every other repository is the in-memory seeded one.
// This lets the redesigned handoff screens be screenshotted with real,
// populated data without touching the owner's Firebase account or credentials.
//
// Run: flutter run -t test/audit_main.dart --dart-define=USE_FIRESTORE=false
// Delete this file when the audit is done.
import 'package:flutter/material.dart';
import 'package:zivo/app/app.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/music/data/fake_music_controller.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const user = AuthUser(
    uid: 'fake-uid',
    email: 'you@zivo.app',
    displayName: 'Ziad',
    isEmailVerified: true,
    providerIds: ['google.com'],
  );
  runApp(
    ZivoApp(
      auth: FakeAuthRepository(initial: const Authenticated(user)),
      profiles: FakeProfileRepository(),
      music: FakeMusicController(),
    ),
  );
}
