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
/// A *split* IS a [WorkoutPlan]; every doc in `workoutPlans` is a split. At most
/// one split is *active* at a time, recorded by an explicit pointer doc at
/// `users/{uid}/workoutMeta/active` = `{ activeSplitId }`. For back-compat with
/// data written before the pointer existed, a missing/empty pointer resolves the
/// active split the old way — the first `status == active` plan, else the first
/// by createdAt.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes the watched streams whenever the uid
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

  // Cached latest snapshots so the sync getters and late subscribers can read
  // the current value without waiting for a new event.
  List<WorkoutPlan> _splitDocs = const <WorkoutPlan>[]; // createdAt ascending
  String? _activePointerId;
  WorkoutPlan? _activePlan;

  // Emission gate: only publish once the splits collection has produced a
  // snapshot for the current uid, so a pointer-doc event that arrives first
  // never emits a premature (empty) active value to a late `.first` subscriber.
  bool _hasSplitsSnapshot = false;
  // True once we have emitted at least one value for the current session, so a
  // late subscriber gets the cached value replayed immediately.
  bool _hasSnapshot = false;

  StreamController<WorkoutPlan?>? _planController;
  StreamController<List<WorkoutPlan>>? _splitsController;
  int _listenerCount = 0;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _splitsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pointerSub;

  // --- Back-compat facade over the active split ---

  @override
  WorkoutPlan? get activePlan => _activePlan;

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    _planController ??= StreamController<WorkoutPlan?>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    // A broadcast stream never replays its latest value to a *late* subscriber.
    // The Today dashboard subscribes first (it stays alive in the shell's
    // IndexedStack) and consumes the initial snapshot, so the Workout page
    // opened afterwards would otherwise sit on ConnectionState.waiting forever
    // whenever there is no active plan. Replay the cached plan on subscribe so
    // every listener sees the current value immediately — matching the
    // in-memory repo contract the pages and tests rely on.
    if (_hasSnapshot) yield _activePlan;
    yield* _planController!.stream;
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) {
    // Back-compat: the single-plan API always made the saved plan THE active
    // plan (the old impl replaced its one slot; every test double sets
    // `_active = plan`, and workout_plan_page_test relies on it). Preserve that —
    // save/replace by id, then point the active pointer at it. saveSplit (the new
    // multi-split API) does NOT steal active.
    final uid = _requireUid();
    final normalized = normalizeWorkoutPlanOrder(plan);
    return _writeSplitDoc(uid, normalized).then((_) => _writePointer(uid, normalized.id));
  }

  @override
  Future<void> deletePlan(String id) => deleteSplit(id);

  // --- Multi-split API ---

  @override
  List<WorkoutPlan> get splits => List<WorkoutPlan>.unmodifiable(_splitDocs);

  @override
  Stream<List<WorkoutPlan>> watchSplits() async* {
    _splitsController ??= StreamController<List<WorkoutPlan>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    if (_hasSnapshot) yield List<WorkoutPlan>.unmodifiable(_splitDocs);
    yield* _splitsController!.stream;
  }

  @override
  String? get activeSplitId => _activePlan?.id;

  @override
  Future<void> setActiveSplit(String id) {
    final uid = _requireUid();
    return _setActiveSplit(uid, id);
  }

  Future<void> _setActiveSplit(String uid, String id) async {
    final doc = await _workoutPlansCollection(uid).doc(id).get();
    if (!doc.exists) {
      throw StateError('setActiveSplit: no split with id "$id".');
    }
    await _writePointer(uid, id);
  }

  @override
  Future<void> saveSplit(WorkoutPlan plan) {
    final uid = _requireUid();
    final normalized = normalizeWorkoutPlanOrder(plan);
    return _saveSplit(uid, normalized);
  }

  Future<void> _saveSplit(String uid, WorkoutPlan normalized) async {
    // Only the first split ever saved (no active split yet) becomes active;
    // saving a second split must leave the current active pointer untouched.
    final activeBefore = await _activeSplitIdFromServer(uid);
    await _writeSplitDoc(uid, normalized);
    if (activeBefore == null) {
      await _writePointer(uid, normalized.id);
    }
  }

  @override
  Future<void> deleteSplit(String id) {
    final uid = _requireUid();
    return _deleteSplit(uid, id);
  }

  Future<void> _deleteSplit(String uid, String id) async {
    await _workoutPlansCollection(uid).doc(id).delete();
    final pointerSnap = await _metaDoc(uid).get();
    if (_pointerIdFrom(pointerSnap.data()) != id) return;
    // The deleted split was active: repoint to the first remaining split in
    // createdAt order, or clear the pointer if none remain.
    final remaining = await _workoutPlansCollection(uid).orderBy('createdAt').get();
    await _writePointer(uid, remaining.docs.isEmpty ? null : remaining.docs.first.id);
  }

  // --- Stream lifecycle (shared by watchActivePlan + watchSplits) ---

  void _onListen() {
    _listenerCount++;
    if (_listenerCount == 1) _start();
  }

  void _onCancel() {
    _listenerCount--;
    if (_listenerCount <= 0) {
      _listenerCount = 0;
      _stop();
    }
  }

  void _start() {
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  void _stop() {
    _uidSub?.cancel();
    _uidSub = null;
    _splitsSub?.cancel();
    _splitsSub = null;
    _pointerSub?.cancel();
    _pointerSub = null;
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onUidChanged(String? uid) {
    _splitsSub?.cancel();
    _pointerSub?.cancel();
    _splitsSub = null;
    _pointerSub = null;
    // Re-arm the emission gate so a stale pointer/collection event from the
    // previous uid cannot leak into the new session.
    _hasSplitsSnapshot = false;

    if (uid == null) {
      _splitDocs = const <WorkoutPlan>[];
      _activePointerId = null;
      _hasSplitsSnapshot = true;
      _emitFromCache();
      return;
    }

    _splitsSub = _workoutPlansCollection(uid)
        .orderBy('createdAt')
        .snapshots()
        .listen((snapshot) {
          _splitDocs = snapshot.docs.map(_planFromDoc).toList(growable: false);
          _hasSplitsSnapshot = true;
          _emitFromCache();
        }, onError: _onStreamError);

    _pointerSub = _metaDoc(uid).snapshots().listen((snapshot) {
      _activePointerId = _pointerIdFrom(snapshot.data());
      _emitFromCache();
    }, onError: _onStreamError);
  }

  void _onStreamError(Object error, StackTrace stack) {
    _planController?.addError(error, stack);
    _splitsController?.addError(error, stack);
  }

  void _emitFromCache() {
    if (!_hasSplitsSnapshot) return;
    _hasSnapshot = true;
    _activePlan = _resolveActive();
    _planController?.add(_activePlan);
    _splitsController?.add(List<WorkoutPlan>.unmodifiable(_splitDocs));
  }

  /// The active split: the one whose id == the pointer; falling back (for
  /// back-compat when no valid pointer is set) to the first `active`-status
  /// split, then the first split (createdAt order), then null.
  WorkoutPlan? _resolveActive() {
    if (_splitDocs.isEmpty) return null;
    final pointer = _activePointerId;
    if (pointer != null) {
      for (final split in _splitDocs) {
        if (split.id == pointer) return split;
      }
    }
    for (final split in _splitDocs) {
      if (split.status == WorkoutPlanStatus.active) return split;
    }
    return _splitDocs.first; // _splitDocs is createdAt ascending.
  }

  // --- Firestore reads/writes ---

  /// Resolves the currently-active split id straight from the server (used by
  /// [saveSplit] to decide whether the incoming split should become active).
  /// Mirrors [_resolveActive]: pointer if valid, else first active-status, else
  /// first by createdAt, else null when there are no splits.
  Future<String?> _activeSplitIdFromServer(String uid) async {
    final pointerSnap = await _metaDoc(uid).get();
    final pointer = _pointerIdFrom(pointerSnap.data());
    final query = await _workoutPlansCollection(uid).orderBy('createdAt').get();
    final plans = query.docs.map(_planFromDoc).toList(growable: false);
    if (plans.isEmpty) return null;
    if (pointer != null) {
      for (final plan in plans) {
        if (plan.id == pointer) return plan.id;
      }
    }
    for (final plan in plans) {
      if (plan.status == WorkoutPlanStatus.active) return plan.id;
    }
    return plans.first.id;
  }

  Future<void> _writeSplitDoc(String uid, WorkoutPlan normalized) {
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

  Future<void> _writePointer(String uid, String? activeSplitId) =>
      _metaDoc(uid).set({'activeSplitId': activeSplitId}, SetOptions(merge: true));

  String? _pointerIdFrom(Map<String, dynamic>? data) {
    final id = data?['activeSplitId'];
    return (id is String && id.isNotEmpty) ? id : null;
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

  DocumentReference<Map<String, dynamic>> _metaDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('workoutMeta').doc('active');

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
