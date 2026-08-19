import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/planned_exercise.dart';
import '../domain/rep_target.dart';
import '../domain/set_type.dart';
import '../domain/workout_day.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_plan_normalize.dart';
import '../domain/workout_plan_repository.dart';
import '../domain/workout_plan_source.dart';
import '../domain/workout_plan_status.dart';
import '../domain/workout_set.dart';

/// The real [WorkoutPlanRepository], backed by Firestore's
/// `users/{uid}/workoutPlans` subcollection. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [WorkoutPlan]/[WorkoutDay]/[PlannedExercise]/[PlannedSet] models.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchActivePlan()` whenever the uid
/// changes (including to/from signed-out).
///
/// Each [WorkoutPlan] embeds its bounded `days → exercises → sets` tree as a
/// plain array field (mirroring Diet's embedded meals/items), always loaded
/// with the parent.
class FirestoreWorkoutPlanRepository implements WorkoutPlanRepository {
  FirestoreWorkoutPlanRepository({FirebaseFirestore? firestore, required this.uidSource})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  WorkoutPlan? _activePlan;
  bool _hasPlanSnapshot = false;
  StreamController<WorkoutPlan?>? _planController;
  StreamSubscription<String?>? _planUidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _planQuerySub;

  @override
  WorkoutPlan? get activePlan => _activePlan;

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    _planController ??= StreamController<WorkoutPlan?>.broadcast(
      onListen: _startPlan,
      onCancel: _stopPlan,
    );
    // A broadcast stream never replays its latest value to a *late* subscriber.
    // The Today dashboard subscribes first (it stays alive in the shell's
    // IndexedStack) and consumes the initial snapshot, so the Workout page
    // opened afterwards would otherwise sit on ConnectionState.waiting forever
    // whenever there is no active plan. Replay the cached plan on subscribe so
    // every listener sees the current value immediately — matching the
    // in-memory repo contract the pages and tests rely on.
    if (_hasPlanSnapshot) yield _activePlan;
    yield* _planController!.stream;
  }

  void _startPlan() {
    _planUidSub = _uidWithInitial().listen(_onPlanUidChanged);
  }

  void _stopPlan() {
    _planUidSub?.cancel();
    _planUidSub = null;
    _planQuerySub?.cancel();
    _planQuerySub = null;
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onPlanUidChanged(String? uid) {
    _planQuerySub?.cancel();
    if (uid == null) {
      _emitPlan(null);
      return;
    }
    _planQuerySub = _workoutPlansCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          final plans = snapshot.docs.map(_planFromDoc).toList(growable: false);
          _emitPlan(_firstActive(plans));
        }, onError: (e, s) => _planController?.addError(e, s));
  }

  WorkoutPlan? _firstActive(List<WorkoutPlan> plans) {
    for (final plan in plans) {
      if (plan.status == WorkoutPlanStatus.active) return plan;
    }
    return null;
  }

  void _emitPlan(WorkoutPlan? plan) {
    _activePlan = plan;
    _hasPlanSnapshot = true;
    _planController?.add(_activePlan);
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) {
    final uid = _requireUid();
    final normalized = normalizeWorkoutPlanOrder(plan);
    return _workoutPlansCollection(uid).doc(normalized.id).set({
      'name': normalized.name,
      'status': normalized.status.name,
      'source': normalized.source.name,
      'cycleCursor': normalized.cycleCursor,
      'days': normalized.days.map(_dayToMap).toList(),
      'schemaVersion': 1,
      'createdAt': Timestamp.fromDate(normalized.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deletePlan(String id) {
    final uid = _requireUid();
    return _workoutPlansCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreWorkoutPlanRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _workoutPlansCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('workoutPlans');

  Map<String, dynamic> _dayToMap(WorkoutDay day) => {
    'id': day.id,
    'slot': day.slot,
    'label': day.label,
    'notes': day.notes,
    'order': day.order,
    'exercises': day.exercises.map(_exerciseToMap).toList(),
  };

  Map<String, dynamic> _exerciseToMap(PlannedExercise exercise) => {
    'id': exercise.id,
    'name': exercise.name,
    'order': exercise.order,
    'muscleGroup': exercise.muscleGroup,
    'notes': exercise.notes,
    'defaultRestSeconds': exercise.defaultRestSeconds,
    'sets': exercise.sets.map(_setToMap).toList(),
  };

  Map<String, dynamic> _setToMap(PlannedSet set) => {
    'order': set.order,
    'repKind': set.repTarget.kind.name,
    'repMin': set.repTarget.min,
    'repMax': set.repTarget.max,
    'restSeconds': set.restSeconds,
    'targetWeightKg': set.targetWeightKg,
    'rpe': set.rpe,
    'type': set.type.name,
  };

  WorkoutPlan _planFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    final rawDays = (data['days'] as List<dynamic>?) ?? const [];
    return WorkoutPlan(
      id: doc.id,
      name: data['name'] as String? ?? '',
      status: workoutPlanStatusFromName(data['status'] as String?),
      source: workoutPlanSourceFromName(data['source'] as String?),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
      cycleCursor: (data['cycleCursor'] as num?)?.toInt() ?? 0,
      days: rawDays.map(_dayFromMap).toList(growable: false),
    );
  }

  WorkoutDay _dayFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    final rawExercises = (map['exercises'] as List<dynamic>?) ?? const [];
    return WorkoutDay(
      id: map['id'] as String? ?? '',
      slot: map['slot'] as String? ?? '',
      label: map['label'] as String? ?? '',
      notes: map['notes'] as String?,
      order: (map['order'] as num?)?.toInt() ?? 0,
      exercises: rawExercises.map(_exerciseFromMap).toList(growable: false),
    );
  }

  PlannedExercise _exerciseFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    final rawSets = (map['sets'] as List<dynamic>?) ?? const [];
    return PlannedExercise(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      muscleGroup: map['muscleGroup'] as String?,
      notes: map['notes'] as String?,
      defaultRestSeconds: (map['defaultRestSeconds'] as num?)?.toInt() ?? 0,
      sets: rawSets.map(_setFromMap).toList(growable: false),
    );
  }

  PlannedSet _setFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return PlannedSet(
      order: (map['order'] as num?)?.toInt() ?? 0,
      repTarget: _repTargetFromMap(map),
      restSeconds: (map['restSeconds'] as num?)?.toInt() ?? 0,
      targetWeightKg: (map['targetWeightKg'] as num?)?.toDouble(),
      rpe: (map['rpe'] as num?)?.toDouble(),
      type: setTypeFromName(map['type'] as String?),
    );
  }

  RepTarget _repTargetFromMap(Map<String, dynamic> map) {
    final kind = repTargetKindFromName(map['repKind'] as String?);
    final min = (map['repMin'] as num?)?.toInt();
    final max = (map['repMax'] as num?)?.toInt();
    switch (kind) {
      case RepTargetKind.fixed:
        return RepTarget.fixed(min ?? 0);
      case RepTargetKind.range:
        return RepTarget.range(min ?? 0, max ?? (min ?? 0));
      case RepTargetKind.toFailure:
        return const RepTarget.toFailure();
    }
  }
}
