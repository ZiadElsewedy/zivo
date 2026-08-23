import 'dart:async';

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
  //
  // Deliberately NOT awaited: `activate` does a network round-trip (token
  // exchange / Play Integrity), but the token is only needed at the first
  // backend call, not to render the first frame. Awaiting it here just delays
  // startup; the SDK gates outbound calls on the token internally, so starting
  // activation and letting it resolve in the background is safe. Errors are
  // swallowed so a rejected/unregistered debug token can't surface as an
  // unhandled async error — a failed attestation only affects backend calls,
  // which fail loudly on their own.
  final useDebugAppCheck =
      AppEnvironment.appCheckMode == AppCheckMode.debug;
  // A fixed debug token (from `--dart-define=APP_CHECK_DEBUG_TOKEN`) keeps the
  // debug attestation STABLE across reinstalls, so it only has to be registered
  // in the Console once. Null → the SDK generates+logs a per-install token (the
  // prior behaviour). Only ever consulted on the debug-provider path.
  final debugToken = AppEnvironment.appCheckDebugToken.isEmpty
      ? null
      : AppEnvironment.appCheckDebugToken;
  unawaited(
    FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugAppCheck
          ? AndroidDebugProvider(debugToken: debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebugAppCheck
          ? AppleDebugProvider(debugToken: debugToken)
          : const AppleAppAttestProvider(),
    ).catchError((_) {}),
  );

  runApp(const ZivoApp());
}
