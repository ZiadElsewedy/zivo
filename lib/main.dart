import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/env/app_environment.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // cloud_firestore already defaults persistence on for iOS/Android — this
  // makes that explicit and pins the cache to unlimited (rather than the
  // 40MB default), since every feature repository (including live workout
  // sessions) reads/writes through Firestore's cache-first SDK and should
  // keep fully working offline. Not applicable on web's own persistence
  // model, and must run before any Firestore read/write.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

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
