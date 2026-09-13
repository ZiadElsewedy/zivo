import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/firebase/uid_source.dart';
import '../step_day_repository.dart';

/// The real [StepDayRepository]: one document per day at
/// `users/{uid}/stepDays/{yyyy-MM-dd}` holding `{steps, updatedAt}`, shape-pinned
/// by `firestore.rules` (owner-only, `steps` a non-negative int).
///
/// Best-effort: [record] no-ops while signed out rather than throwing, because
/// it is called from a background step listener, not a user action.
class FirestoreStepDayRepository implements StepDayRepository {
  FirestoreStepDayRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  @override
  Future<void> record(DateTime day, int steps) async {
    final uid = uidSource.currentUid();
    if (uid == null) return;
    if (steps < 0) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('stepDays')
        .doc(stepDayKey(day))
        .set({
          'steps': steps,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
