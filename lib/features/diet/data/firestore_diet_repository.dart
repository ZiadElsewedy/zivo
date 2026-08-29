import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/diet_day.dart';
import '../domain/diet_plan.dart';
import '../domain/diet_plan_status.dart';
import '../domain/diet_repository.dart';
import '../domain/diet_source.dart';
import '../domain/diet_goal.dart';
import '../domain/food_item.dart';
import '../domain/meal.dart';
import '../domain/nutrition_targets.dart';

/// The real [DietRepository], backed by Firestore's `users/{uid}/dietPlans`
/// and `users/{uid}/dietEntries` subcollections. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [DietPlan]/[DietDay]/[Meal]/[FoodItem] models.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes both `watchActivePlan()` and
/// `watchConsumed()` whenever the uid changes (including to/from signed-out).
///
/// Each [DietPlan] embeds its bounded `days → meals → items` tree as a plain
/// array field (mirroring Workout's embedded exercises), always loaded with
/// the parent. `dietEntries` is a separate, unbounded, append-over-time log —
/// one doc per (day, meal) — so it is its own subcollection, queried by the
/// equality-only `dayKey` field (no composite index required).
///
/// Targets live at the single fixed document `dietTargets/current` (the same
/// "one pointer doc" shape `workoutMeta/active` uses): there is only ever one
/// active objective, and a fixed id makes reading it a get rather than a
/// query. A MISSING doc is the meaningful "no target set" state — surfaced as
/// null, never defaulted into a number nobody chose.
class FirestoreDietRepository implements DietRepository {
  FirestoreDietRepository({FirebaseFirestore? firestore, required this.uidSource})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  DietPlan? _activePlan;
  bool _hasPlanSnapshot = false;
  StreamController<DietPlan?>? _planController;
  StreamSubscription<String?>? _planUidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _planQuerySub;

  NutritionTargets? _targets;
  bool _hasTargetsSnapshot = false;
  StreamController<NutritionTargets?>? _targetsController;
  StreamSubscription<String?>? _targetsUidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _targetsDocSub;

  @override
  DietPlan? get activePlan => _activePlan;

  @override
  Stream<DietPlan?> watchActivePlan() async* {
    _planController ??= StreamController<DietPlan?>.broadcast(
      onListen: _startPlan,
      onCancel: _stopPlan,
    );
    // A broadcast stream never replays its latest value to a *late* subscriber.
    // The Today dashboard subscribes first (it stays alive in the shell's
    // IndexedStack) and consumes the initial snapshot, so the Diet page opened
    // afterwards would otherwise sit on ConnectionState.waiting forever whenever
    // there is no active plan. Replay the cached plan on subscribe so every
    // listener sees the current value immediately — matching the in-memory repo
    // contract the pages and tests rely on.
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
    _planQuerySub = _dietPlansCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          final plans = snapshot.docs.map(_planFromDoc).toList(growable: false);
          _emitPlan(_firstActive(plans));
        }, onError: (e, s) => _planController?.addError(e, s));
  }

  DietPlan? _firstActive(List<DietPlan> plans) {
    for (final plan in plans) {
      if (plan.status == DietPlanStatus.active) return plan;
    }
    return null;
  }

  void _emitPlan(DietPlan? plan) {
    _activePlan = plan;
    _hasPlanSnapshot = true;
    _planController?.add(_activePlan);
  }

  @override
  NutritionTargets? get currentTargets => _targets;

  /// Mirrors [watchActivePlan]'s replay-on-subscribe contract for exactly the
  /// same reason: Today and Diet both listen, and a late subscriber to a
  /// broadcast stream would otherwise sit on `waiting` forever whenever the
  /// value is null — which, for targets, is the common case.
  @override
  Stream<NutritionTargets?> watchTargets() async* {
    _targetsController ??= StreamController<NutritionTargets?>.broadcast(
      onListen: _startTargets,
      onCancel: _stopTargets,
    );
    if (_hasTargetsSnapshot) yield _targets;
    yield* _targetsController!.stream;
  }

  void _startTargets() {
    _targetsUidSub = _uidWithInitial().listen(_onTargetsUidChanged);
  }

  void _stopTargets() {
    _targetsUidSub?.cancel();
    _targetsUidSub = null;
    _targetsDocSub?.cancel();
    _targetsDocSub = null;
  }

  void _onTargetsUidChanged(String? uid) {
    _targetsDocSub?.cancel();
    if (uid == null) {
      _emitTargets(null);
      return;
    }
    _targetsDocSub = _targetsDoc(uid).snapshots().listen((snapshot) {
      _emitTargets(snapshot.exists ? _targetsFromMap(snapshot.data()) : null);
    }, onError: (e, s) => _targetsController?.addError(e, s));
  }

  void _emitTargets(NutritionTargets? targets) {
    _targets = targets;
    _hasTargetsSnapshot = true;
    _targetsController?.add(_targets);
  }

  @override
  Future<void> saveTargets(NutritionTargets targets) {
    final uid = _requireUid();
    final basis = targets.basis;
    return _targetsDoc(uid).set({
      'goal': targets.goal.name,
      'calories': targets.calories,
      'proteinG': targets.proteinG,
      'carbsG': targets.carbsG,
      'fatG': targets.fatG,
      'source': targets.source.name,
      // The inputs behind a calculated figure travel with it, so the number
      // can always be explained and recomputed. Absent for a manual target.
      'basis': basis == null
          ? null
          : {
              'weightKg': basis.weightKg,
              'heightCm': basis.heightCm,
              'age': basis.age,
              'sex': basis.sex.name,
              'activity': basis.activity.name,
              'bmr': basis.bmr,
              'maintenanceCalories': basis.maintenanceCalories,
            },
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearTargets() {
    final uid = _requireUid();
    return _targetsDoc(uid).delete();
  }

  @override
  Future<void> savePlan(DietPlan plan) {
    final uid = _requireUid();
    return _dietPlansCollection(uid).doc(plan.id).set({
      'name': plan.name,
      'status': plan.status.name,
      'source': plan.source.name,
      'days': plan.days.map(_dayToMap).toList(),
      'schemaVersion': 1,
      'createdAt': Timestamp.fromDate(plan.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deletePlan(String id) {
    final uid = _requireUid();
    return _dietPlansCollection(uid).doc(id).delete();
  }

  /// Independent per-call stream: [watchConsumed] is parameterized by [day],
  /// so (unlike [watchActivePlan]'s single cached controller) each call opens
  /// its own uid-scoped subscription rather than sharing one controller.
  @override
  Stream<Set<String>> watchConsumed(DateTime day) {
    final key = dayKey(day);
    late final StreamController<Set<String>> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;

    void onUidChanged(String? uid) {
      querySub?.cancel();
      if (uid == null) {
        controller.add(const <String>{});
        return;
      }
      querySub = _dietEntriesCollection(uid)
          .where('dayKey', isEqualTo: key)
          .snapshots()
          .listen((snapshot) {
            final eaten = <String>{};
            for (final doc in snapshot.docs) {
              final data = doc.data();
              if ((data['eaten'] as bool?) ?? false) {
                final mealId = data['mealId'] as String?;
                if (mealId != null) eaten.add(mealId);
              }
            }
            controller.add(eaten);
          }, onError: (e, s) => controller.addError(e, s));
    }

    controller = StreamController<Set<String>>.broadcast(
      onListen: () => uidSub = _uidWithInitial().listen(onUidChanged),
      onCancel: () {
        uidSub?.cancel();
        uidSub = null;
        querySub?.cancel();
        querySub = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) {
    final uid = _requireUid();
    final key = dayKey(day);
    final startOfDay = DateTime(day.year, day.month, day.day);
    return _dietEntriesCollection(uid).doc('${key}__$mealId').set({
      'dayKey': key,
      'date': Timestamp.fromDate(startOfDay),
      'mealId': mealId,
      'eaten': eaten,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreDietRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _dietPlansCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('dietPlans');

  CollectionReference<Map<String, dynamic>> _dietEntriesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('dietEntries');

  DocumentReference<Map<String, dynamic>> _targetsDoc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('dietTargets')
      .doc('current');

  /// Reads a stored targets document. Returns null when the document can't be
  /// read as a real target — a missing goal, or a missing/invalid calorie
  /// figure, means "not set", never a partially-invented target.
  NutritionTargets? _targetsFromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final goal = dietGoalFromName(data['goal'] as String?);
    final calories = (data['calories'] as num?)?.toInt();
    if (goal == null || calories == null || calories <= 0) return null;
    final updatedAt = data['updatedAt'];
    return NutritionTargets(
      goal: goal,
      calories: calories,
      proteinG: (data['proteinG'] as num?)?.toDouble(),
      carbsG: (data['carbsG'] as num?)?.toDouble(),
      fatG: (data['fatG'] as num?)?.toDouble(),
      source: targetSourceFromName(data['source'] as String?),
      basis: _basisFromMap(data['basis']),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }

  /// A calculated target's inputs. Null unless every field is present — a
  /// half-read basis would explain the number wrongly, which is worse than
  /// not explaining it at all.
  TargetBasis? _basisFromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final weightKg = (map['weightKg'] as num?)?.toDouble();
    final heightCm = (map['heightCm'] as num?)?.toDouble();
    final age = (map['age'] as num?)?.toInt();
    final sex = targetSexFromName(map['sex'] as String?);
    final activity = activityLevelFromName(map['activity'] as String?);
    final bmr = (map['bmr'] as num?)?.toInt();
    final maintenance = (map['maintenanceCalories'] as num?)?.toInt();
    if (weightKg == null ||
        heightCm == null ||
        age == null ||
        sex == null ||
        activity == null ||
        bmr == null ||
        maintenance == null) {
      return null;
    }
    return TargetBasis(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      sex: sex,
      activity: activity,
      bmr: bmr,
      maintenanceCalories: maintenance,
    );
  }

  Map<String, dynamic> _dayToMap(DietDay day) => {
    'weekday': day.weekday,
    'label': day.label,
    'meals': day.meals.map(_mealToMap).toList(),
  };

  Map<String, dynamic> _mealToMap(Meal meal) => {
    'id': meal.id,
    'label': meal.label,
    'order': meal.order,
    'items': meal.items.map(_itemToMap).toList(),
  };

  Map<String, dynamic> _itemToMap(FoodItem item) => {
    'name': item.name,
    'quantity': item.quantity,
    'unit': item.unit,
    'calories': item.calories,
    'proteinG': item.proteinG,
    'carbsG': item.carbsG,
    'fatG': item.fatG,
    'estimated': item.estimated,
  };

  DietPlan _planFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    final rawDays = (data['days'] as List<dynamic>?) ?? const [];
    return DietPlan(
      id: doc.id,
      name: data['name'] as String? ?? '',
      status: dietPlanStatusFromName(data['status'] as String?),
      source: dietSourceFromName(data['source'] as String?),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
      days: rawDays.map(_dayFromMap).toList(growable: false),
    );
  }

  DietDay _dayFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    final rawMeals = (map['meals'] as List<dynamic>?) ?? const [];
    return DietDay(
      weekday: (map['weekday'] as num?)?.toInt(),
      label: map['label'] as String? ?? '',
      meals: rawMeals.map(_mealFromMap).toList(growable: false),
    );
  }

  Meal _mealFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    final rawItems = (map['items'] as List<dynamic>?) ?? const [];
    return Meal(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      items: rawItems.map(_itemFromMap).toList(growable: false),
    );
  }

  FoodItem _itemFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return FoodItem(
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: map['unit'] as String? ?? '',
      calories: (map['calories'] as num?)?.toInt(),
      proteinG: (map['proteinG'] as num?)?.toDouble(),
      carbsG: (map['carbsG'] as num?)?.toDouble(),
      fatG: (map['fatG'] as num?)?.toDouble(),
      estimated: map['estimated'] == true,
    );
  }
}

/// 'yyyy-MM-dd' for [day]'s local calendar date — used both as the
/// `dietEntries` doc id suffix and its `dayKey` field. Exposed so tests can
/// build the same key without duplicating the format.
String dayKey(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}
