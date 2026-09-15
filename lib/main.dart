import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/env/app_environment.dart';
import 'firebase_options.dart';

/// Emulator Suite ports. Kept in sync with the `emulators` block in
/// `firebase.json` — change both together.
const int _authEmulatorPort = 9099;
const int _firestoreEmulatorPort = 8080;
const int _functionsEmulatorPort = 5001;
const int _storageEmulatorPort = 9199;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final useEmulator = AppEnvironment.useFirebaseEmulator;

  // Firestore settings MUST be configured before any read/write — and, when
  // using the emulator, before `useFirestoreEmulator` below.
  //
  // cloud_firestore already defaults persistence on for iOS/Android — this
  // makes that explicit and pins the cache to unlimited (rather than the
  // 40MB default), since every feature repository (including live workout
  // sessions) reads/writes through Firestore's cache-first SDK and should
  // keep fully working offline. Not applicable on web's own persistence model.
  //
  // Persistence is turned OFF against the emulator: a disk cache would mask an
  // emulator reset (stale docs surviving `firebase emulators:start` with a
  // fresh dataset), which defeats the point of a disposable environment.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: !useEmulator,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Demo/experimentation environment: when opted in (debug/profile only — the
  // flag is hard-off in release), point every Firebase SDK at the local
  // Emulator Suite instead of the live `zivo-63f15` backend.
  //
  // Order matters: `useFirestoreEmulator` applies the emulator host by doing
  // `settings = settings.copyWith(host: ..., sslEnabled: false)`, so it must
  // run AFTER the `settings =` assignment above — which preserves our
  // persistence/cache choices. Doing it the other way round replaces the
  // settings object and silently reverts Firestore to the production host,
  // which (with persistence off) fails the first read as
  // `[unavailable] client is offline`.
  if (useEmulator) {
    final host = AppEnvironment.emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, _authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, _firestoreEmulatorPort);
    FirebaseFunctions.instance.useFunctionsEmulator(host, _functionsEmulatorPort);
    await FirebaseStorage.instance.useStorageEmulator(host, _storageEmulatorPort);
  }

  runApp(const ZivoApp());
}
