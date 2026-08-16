import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/env/app_environment.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check attests that calls to our backend (notably the `aiChat` callable,
  // which spends real Anthropic budget) come from a genuine app instance. The
  // mode is resolved centrally by [AppEnvironment]: Development uses the debug
  // providers (register the token the app prints in Firebase Console → App
  // Check → Debug tokens); Profile and Release attest for real — Play Integrity
  // on Android, App Attest on Apple — so a Profile build behaves like production.
  final useDebugAppCheck =
      AppEnvironment.appCheckMode == AppCheckMode.debug;
  await FirebaseAppCheck.instance.activate(
    providerAndroid: useDebugAppCheck
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: useDebugAppCheck
        ? const AppleDebugProvider()
        : const AppleAppAttestProvider(),
  );

  runApp(const ZivoApp());
}
