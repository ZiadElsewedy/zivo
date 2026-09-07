import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../domain/sleep_night.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_targets.dart';
import 'sleep_night_codec.dart';

/// The real [SleepRepository], backed by `users/{uid}/sleepNights` plus a
/// single `users/{uid}/sleepSettings/main` document for targets and the open
/// manual mark.
///
/// Constructed once at app root, before sign-in, so it holds no uid of its own
/// and resolves the signed-in user through [UidSource] — three
/// [UidScopedMirror]s, one per thing it watches, exactly as the diet
/// repository does.
///
/// **Nights are keyed by sleep-day, not by a generated id.** That is the
/// cross-device dedup mechanism: a phone and a tablet resolving the same night
/// write to the same document and converge, instead of racing to create two
/// records of one night.
class FirestoreSleepRepository implements SleepRepository {
  FirestoreSleepRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
    this.historyDays = 120,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _nights = UidScopedMirror<List<SleepNight>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _nightsCollection(uid)
          .orderBy('sleepDay', descending: true)
          .limit(historyDays)
          .snapshots()
          .map(
            (s) => s.docs
                .map((doc) => SleepNightCodec.decodeNight(doc.id, doc.data()))
                .toList(growable: false),
          ),
    )..start();

    _settings = UidScopedMirror<Map<String, dynamic>?>(
      uidSource: uidSource,
      signedOutValue: null,
      source: (uid) => _settingsDoc(uid).snapshots().map((doc) => doc.data()),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  /// How many nights the mirror keeps hot. Four months covers every window the
  /// UI and the metrics ask for (a fortnight of trend, a pair of weeks to
  /// compare) with room to spare, and bounds the listener so a long-running
  /// user does not stream years of history into memory on every launch.
  final int historyDays;

  late final UidScopedMirror<List<SleepNight>> _nights;
  late final UidScopedMirror<Map<String, dynamic>?> _settings;

  @override
  List<SleepNight> get current => List.unmodifiable(_nights.current);

  @override
  Stream<List<SleepNight>> watchNights() => _nights.watch();

  @override
  SleepTargets? get currentTargets => _targetsFrom(_settings.current);

  @override
  Stream<SleepTargets?> watchTargets() => _settings.watch().map(_targetsFrom);

  @override
  SleepMark? get currentOpenMark => _markFrom(_settings.current);

  @override
  Stream<SleepMark?> watchOpenMark() => _settings.watch().map(_markFrom);

  @override
  Future<void> saveTargets(SleepTargets targets) {
    final uid = uidSource.requireUid(this);
    return _settingsDoc(uid).set({
      'schemaVersion': SleepNightCodec.schemaVersion,
      'targets': SleepNightCodec.encodeTargets(targets),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> upsertNights(List<SleepNight> nights) async {
    if (nights.isEmpty) return;
    final uid = uidSource.requireUid(this);
    final collection = _nightsCollection(uid);

    // Batched because a backfill resolves ninety nights at once and ninety
    // round trips is a visibly slow first launch. Firestore caps a batch at
    // 500 writes, so long backfills are chunked rather than assumed to fit.
    const chunkSize = 400;
    for (var i = 0; i < nights.length; i += chunkSize) {
      final chunk = nights.skip(i).take(chunkSize);
      final batch = _firestore.batch();
      for (final night in chunk) {
        batch.set(collection.doc(SleepNightCodec.docId(night.sleepDay)), {
          ...SleepNightCodec.encodeNight(night),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  @override
  Future<void> removeNight(DateTime sleepDay) {
    final uid = uidSource.requireUid(this);
    return _nightsCollection(uid).doc(SleepNightCodec.docId(sleepDay)).delete();
  }

  @override
  Future<void> openMark(SleepMark mark) {
    final uid = uidSource.requireUid(this);
    return _settingsDoc(uid).set({
      'schemaVersion': SleepNightCodec.schemaVersion,
      'openMark': SleepNightCodec.encodeMark(mark),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearOpenMark() {
    final uid = uidSource.requireUid(this);
    return _settingsDoc(uid).set({
      'openMark': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Tears down the always-on listeners — not called in production (the
  /// repository lives for the app's process lifetime), only in tests.
  void dispose() {
    _nights.dispose();
    _settings.dispose();
  }

  CollectionReference<Map<String, dynamic>> _nightsCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('sleepNights');

  DocumentReference<Map<String, dynamic>> _settingsDoc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('sleepSettings')
      .doc('main');

  SleepTargets? _targetsFrom(Map<String, dynamic>? data) {
    final raw = data?['targets'];
    if (raw is! Map) return null;
    return SleepNightCodec.decodeTargets(raw.cast<String, dynamic>());
  }

  SleepMark? _markFrom(Map<String, dynamic>? data) {
    final raw = data?['openMark'];
    if (raw is! Map) return null;
    return SleepNightCodec.decodeMarkOrNull(raw.cast<String, dynamic>());
  }
}
