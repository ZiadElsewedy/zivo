import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check attests that calls to our backend (notably the `aiChat` callable,
  // which spends real Anthropic budget) come from a genuine app instance. In
  // debug builds we use the debug providers — register the token the app prints
  // in Firebase Console → App Check → Debug tokens. Release builds use hardware
  // attestation: Play Integrity on Android, App Attest on Apple.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestProvider(),
  );

  runApp(const ZivoApp());
}
