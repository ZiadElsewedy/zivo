import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app/app.dart';
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

  runApp(const ZivoApp());
}
