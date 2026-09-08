import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../../../core/util/calendar.dart';
import '../domain/training_day_mark.dart';
import '../domain/training_day_mark_repository.dart';

/// The real [TrainingDayMarkRepository], backed by
/// `users/{uid}/trainingDayMarks/{yyyy-MM-dd}` — one document per calendar
/// day, keyed by the day itself, so writing the same mark twice is idempotent
/// and a restore can never be spent twice on one day by accident.
///
/// Reads go through [UidScopedMirror] like every other Firestore repository
/// here: it owns the uid re-scoping, the cached [current], the late-subscriber
/// replay and the always-on listener.
class FirestoreTrainingDayMarkRepository implements TrainingDayMarkRepository {
  FirestoreTrainingDayMarkRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<TrainingDayMark>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _collection(uid)
          .orderBy(FieldPath.documentId, descending: true)
          .snapshots()
          .map(
            (s) => s.docs
                .map(_fromDoc)
                .whereType<TrainingDayMark>()
                .toList(growable: false),
          ),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<TrainingDayMark>> _mirror;

  @override
  List<TrainingDayMark> get current => _mirror.current;

  @override
  Stream<List<TrainingDayMark>> watchAll() => _mirror.watch();

  @override
  Future<void> saveMark(TrainingDayMark mark) {
    final uid = uidSource.requireUid(this);
    return _collection(uid).doc(mark.key).set({
      'dayKey': mark.key,
      'reason': mark.reason?.name,
      'note': mark.note,
      'restored': mark.restored,
      'createdAt': Timestamp.fromDate(mark.createdAt),
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteMark(DateTime day) {
    final uid = uidSource.requireUid(this);
    return _collection(uid).doc(dayKey(day)).delete();
  }

  /// Tears down the always-on listener — not called in production, only for
  /// explicit teardown in tests.
  void dispose() => _mirror.dispose();

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('trainingDayMarks');

  /// Null for a document whose id is not a day key — the id IS the day, so an
  /// unparseable one has no day to be about. Dropped rather than guessed at.
  TrainingDayMark? _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final day = dayFromKey(doc.id);
    if (day == null) return null;
    final data = doc.data();
    final createdAt = data['createdAt'];
    final reason = data['reason'] as String?;
    return TrainingDayMark(
      day: day,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : day,
      reason: reason == null ? null : missedDayReasonFromName(reason),
      note: data['note'] as String?,
      restored: data['restored'] as bool? ?? false,
    );
  }
}
