import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/body_profile.dart';
import '../domain/diet_day.dart';
import '../domain/diet_format.dart';
import '../domain/diet_plan.dart';
import '../domain/diet_plan_status.dart';
import '../domain/diet_repository.dart';
import '../domain/diet_source.dart';
import '../domain/diet_goal.dart';
import '../domain/food_item.dart';
import '../domain/meal.dart';
import '../domain/nutrition/custom_food.dart';
import '../domain/nutrition/food_log_entry.dart';
import '../domain/nutrition/food_reference.dart';
import '../domain/nutrition/planned_meal_log.dart';
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
  FirestoreDietRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  DietPlan? _activePlan;
  List<DietPlan> _plans = const [];
  bool _hasPlanSnapshot = false;
  StreamController<DietPlan?>? _planController;
  StreamController<List<DietPlan>>? _plansController;
  StreamSubscription<String?>? _planUidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _planQuerySub;

  NutritionTargets? _targets;
  bool _hasTargetsSnapshot = false;
  StreamController<NutritionTargets?>? _targetsController;
  StreamSubscription<String?>? _targetsUidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _targetsDocSub;

  BodyProfile? _bodyProfile;
  bool _hasBodyProfileSnapshot = false;
  StreamController<BodyProfile?>? _bodyProfileController;
  StreamSubscription<String?>? _bodyProfileUidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _bodyProfileDocSub;

  @override
  DietPlan? get activePlan => _activePlan;

  @override
  List<DietPlan> get plans => _plans;

  @override
  Stream<DietPlan?> watchActivePlan() async* {
    _planController ??= StreamController<DietPlan?>.broadcast(
      onListen: _startPlanIfNeeded,
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
    _planUidSub?.cancel();
    _planUidSub = _uidWithInitial().listen(_onPlanUidChanged);
  }

  void _stopPlan() {
    // Both plan streams share one query subscription; the last one out turns
    // the light off. Without this check, closing the library screen would
    // silently kill the Diet screen's active-plan stream.
    if (_planController?.hasListener ?? false) return;
    if (_plansController?.hasListener ?? false) return;
    _planUidSub?.cancel();
    _planUidSub = null;
    _planQuerySub?.cancel();
    _planQuerySub = null;
  }

  void _startPlanIfNeeded() {
    if (_planUidSub == null) _startPlan();
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onPlanUidChanged(String? uid) {
    _planQuerySub?.cancel();
    if (uid == null) {
      _emitPlans(const []);
      return;
    }
    _planQuerySub = _dietPlansCollection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) => _emitPlans(
            snapshot.docs.map(_planFromDoc).toList(growable: false),
          ),
          onError: (e, s) {
            _planController?.addError(e, s);
            _plansController?.addError(e, s);
          },
        );
  }

  DietPlan? _firstActive(List<DietPlan> plans) {
    for (final plan in plans) {
      if (plan.status == DietPlanStatus.active) return plan;
    }
    return null;
  }

  /// The library and the active plan come from the **one** query, so the two
  /// streams can never disagree about which plan is in force.
  void _emitPlans(List<DietPlan> plans) {
    _plans = List.unmodifiable(plans);
    _activePlan = _firstActive(plans);
    _hasPlanSnapshot = true;
    _planController?.add(_activePlan);
    _plansController?.add(_plans);
  }

  @override
  Stream<List<DietPlan>> watchPlans() async* {
    _plansController ??= StreamController<List<DietPlan>>.broadcast(
      onListen: _startPlanIfNeeded,
      onCancel: _stopPlan,
    );
    // Same replay-on-subscribe contract as [watchActivePlan] — see its note.
    if (_hasPlanSnapshot) yield _plans;
    yield* _plansController!.stream;
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
  BodyProfile? get currentBodyProfile => _bodyProfile;

  /// Same replay-on-subscribe contract as [watchTargets], and null is just as
  /// common here — a user who hasn't been asked for their body data yet.
  @override
  Stream<BodyProfile?> watchBodyProfile() async* {
    _bodyProfileController ??= StreamController<BodyProfile?>.broadcast(
      onListen: _startBodyProfile,
      onCancel: _stopBodyProfile,
    );
    if (_hasBodyProfileSnapshot) yield _bodyProfile;
    yield* _bodyProfileController!.stream;
  }

  void _startBodyProfile() {
    _bodyProfileUidSub = _uidWithInitial().listen(_onBodyProfileUidChanged);
  }

  void _stopBodyProfile() {
    _bodyProfileUidSub?.cancel();
    _bodyProfileUidSub = null;
    _bodyProfileDocSub?.cancel();
    _bodyProfileDocSub = null;
  }

  void _onBodyProfileUidChanged(String? uid) {
    _bodyProfileDocSub?.cancel();
    if (uid == null) {
      _emitBodyProfile(null);
      return;
    }
    _bodyProfileDocSub = _bodyProfileDoc(uid).snapshots().listen((snapshot) {
      _emitBodyProfile(
        snapshot.exists ? _bodyProfileFromMap(snapshot.data()) : null,
      );
    }, onError: (e, s) => _bodyProfileController?.addError(e, s));
  }

  void _emitBodyProfile(BodyProfile? profile) {
    _bodyProfile = profile;
    _hasBodyProfileSnapshot = true;
    _bodyProfileController?.add(_bodyProfile);
  }

  @override
  Future<void> saveBodyProfile(BodyProfile profile) {
    final uid = _requireUid();
    return _bodyProfileDoc(uid).set({
      'heightCm': profile.heightCm,
      'sex': profile.sex.name,
      'activity': profile.activity.name,
      // Written explicitly as null when absent (not merged away), so clearing
      // a stated maintenance figure actually clears it.
      'statedMaintenanceKcal': profile.statedMaintenanceKcal,
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearBodyProfile() {
    final uid = _requireUid();
    return _bodyProfileDoc(uid).delete();
  }

  @override
  Future<void> savePlan(DietPlan plan) async {
    final uid = _requireUid();
    final batch = _firestore.batch();
    batch.set(_dietPlansCollection(uid).doc(plan.id), {
      'name': plan.name,
      'status': plan.status.name,
      'source': plan.source.name,
      'days': plan.days.map(_dayToMap).toList(),
      'schemaVersion': 1,
      'createdAt': Timestamp.fromDate(plan.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Saving an active plan is also a statement about the others: one plan is
    // in force at a time. Done in the same batch so there is never a moment,
    // even offline, where two documents both claim to be active.
    if (plan.status == DietPlanStatus.active) {
      await _archiveOtherActives(uid, batch, keep: plan.id);
    }
    return batch.commit();
  }

  @override
  Future<void> setActivePlan(String id) async {
    final uid = _requireUid();
    final doc = await _dietPlansCollection(uid).doc(id).get();
    // A plan that isn't there must not leave the user with nothing active.
    if (!doc.exists) return;
    final batch = _firestore.batch();
    batch.update(doc.reference, {
      'status': DietPlanStatus.active.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _archiveOtherActives(uid, batch, keep: id);
    return batch.commit();
  }

  @override
  Future<void> archivePlan(String id) {
    final uid = _requireUid();
    return _dietPlansCollection(uid).doc(id).update({
      'status': DietPlanStatus.archived.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Queues "archive every active plan except [keep]" onto [batch].
  ///
  /// Reads the server's current actives rather than the cached list: the cache
  /// can be cold (nothing has subscribed yet) and a stale one would leave a
  /// second active plan behind — the one state this collection must never be
  /// in.
  Future<void> _archiveOtherActives(
    String uid,
    WriteBatch batch, {
    required String keep,
  }) async {
    final actives = await _dietPlansCollection(
      uid,
    ).where('status', isEqualTo: DietPlanStatus.active.name).get();
    for (final doc in actives.docs) {
      if (doc.id == keep) continue;
      batch.update(doc.reference, {
        'status': DietPlanStatus.archived.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
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
  }) async {
    final uid = _requireUid();
    final key = dayKey(day);
    final startOfDay = DateTime(day.year, day.month, day.day);

    // `dietEntries` stays the tick state and keeps its exact shape — older app
    // builds still read it, and the rules still validate it. What's new is the
    // second write below.
    await _dietEntriesCollection(uid).doc('${key}__$mealId').set({
      'dayKey': key,
      'date': Timestamp.fromDate(startOfDay),
      'mealId': mealId,
      'eaten': eaten,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Materialise the meal into the food log, so "consumed" is a list of foods
    // rather than a checkbox. Ids are derived from (day, meal, index) so the
    // write is idempotent: double-ticking overwrites rather than duplicating.
    final meal = _mealById(mealId);
    if (meal == null) return;
    final entries = entriesForPlannedMeal(
      meal: meal,
      day: day,
      now: DateTime.now(),
      idPrefix: '${key}__$mealId',
    );
    final batch = _firestore.batch();
    if (eaten) {
      for (final entry in entries) {
        batch.set(
          _foodLogsCollection(uid).doc(entry.id),
          _entryToMap(entry),
          SetOptions(merge: true),
        );
      }
    } else {
      // Remove exactly the entries this meal created — never a user's own.
      for (final entry in entries) {
        batch.delete(_foodLogsCollection(uid).doc(entry.id));
      }
    }
    await batch.commit();
  }

  /// The meal with [mealId] in the cached active plan, or null.
  Meal? _mealById(String mealId) {
    for (final day in _activePlan?.days ?? const <DietDay>[]) {
      for (final meal in day.meals) {
        if (meal.id == mealId) return meal;
      }
    }
    return null;
  }

  /// Independent per-call stream, for the same reason [watchConsumed] is one:
  /// it is parameterized by the day being watched.
  @override
  Stream<List<FoodLogEntry>> watchFoodLog(DateTime day) {
    final key = dayKey(day);
    late final StreamController<List<FoodLogEntry>> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;

    void onUidChanged(String? uid) {
      querySub?.cancel();
      if (uid == null) {
        controller.add(const []);
        return;
      }
      querySub = _foodLogsCollection(uid)
          .where('dayKey', isEqualTo: key)
          .snapshots()
          .listen((snapshot) {
            final entries =
                snapshot.docs
                    .map(_entryFromDoc)
                    .whereType<FoodLogEntry>()
                    .toList()
                  ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
            controller.add(entries);
          }, onError: (e, s) => controller.addError(e, s));
    }

    controller = StreamController<List<FoodLogEntry>>.broadcast(
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
  Future<void> logFood(List<FoodLogEntry> entries) async {
    if (entries.isEmpty) return;
    final uid = _requireUid();
    final batch = _firestore.batch();
    for (final entry in entries) {
      batch.set(_foodLogsCollection(uid).doc(entry.id), _entryToMap(entry));
    }
    // One batch: "two eggs and 100g rice" is one thing the user said, and it
    // should land whole or not at all.
    await batch.commit();
  }

  @override
  Future<void> removeFoodLogEntry(String id) {
    final uid = _requireUid();
    return _foodLogsCollection(uid).doc(id).delete();
  }

  @override
  Stream<List<CustomFood>> watchCustomFoods() {
    late final StreamController<List<CustomFood>> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;

    void onUidChanged(String? uid) {
      querySub?.cancel();
      if (uid == null) {
        controller.add(const []);
        return;
      }
      querySub = _customFoodsCollection(uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            controller.add(
              snapshot.docs
                  .map(_customFoodFromDoc)
                  .whereType<CustomFood>()
                  .toList(),
            );
          }, onError: (e, s) => controller.addError(e, s));
    }

    controller = StreamController<List<CustomFood>>.broadcast(
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
  Future<List<CustomFood>> listCustomFoods() async {
    final uid = uidSource.currentUid();
    if (uid == null) return const [];
    final snapshot = await _customFoodsCollection(
      uid,
    ).orderBy('createdAt', descending: true).get();
    return snapshot.docs
        .map(_customFoodFromDoc)
        .whereType<CustomFood>()
        .toList();
  }

  @override
  Future<void> saveCustomFood(CustomFood food) {
    final uid = _requireUid();
    return _customFoodsCollection(uid).doc(food.id).set({
      'name': food.name,
      'kcalPer100g': food.kcalPer100g,
      'proteinPer100g': food.proteinPer100g,
      'carbsPer100g': food.carbsPer100g,
      'fatPer100g': food.fatPer100g,
      'preparation': food.preparation.name,
      'portions': [
        for (final portion in food.portions)
          {'label': portion.label, 'grams': portion.grams},
      ],
      'schemaVersion': 1,
      'createdAt': Timestamp.fromDate(food.createdAt),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteCustomFood(String id) {
    final uid = _requireUid();
    return _customFoodsCollection(uid).doc(id).delete();
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

  CollectionReference<Map<String, dynamic>> _dietEntriesCollection(
    String uid,
  ) => _firestore.collection('users').doc(uid).collection('dietEntries');

  CollectionReference<Map<String, dynamic>> _foodLogsCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('foodLogs');

  CollectionReference<Map<String, dynamic>> _customFoodsCollection(
    String uid,
  ) => _firestore.collection('users').doc(uid).collection('customFoods');

  /// The stored shape of a log entry. The computed nutrition is stored
  /// alongside the food reference on purpose: the catalog can be rebuilt, and
  /// a past day must not silently change its totals when it is.
  Map<String, dynamic> _entryToMap(FoodLogEntry entry) => {
    'dayKey': dayKey(entry.day),
    'date': Timestamp.fromDate(entry.day),
    'loggedAt': Timestamp.fromDate(entry.loggedAt),
    'foodId': entry.foodId,
    'foodName': entry.foodName,
    'quantity': entry.quantity,
    'unit': entry.unit,
    'grams': entry.grams,
    'kcal': entry.kcal,
    'proteinG': entry.proteinG,
    'carbsG': entry.carbsG,
    'fatG': entry.fatG,
    'source': entry.source.name,
    'sourceRef': entry.sourceRef,
    'origin': entry.origin.name,
    'estimated': entry.estimated,
    'mealId': entry.mealId,
    'schemaVersion': 1,
  };

  FoodLogEntry? _entryFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final foodId = data['foodId'] as String?;
    final date = data['date'];
    if (foodId == null || foodId.isEmpty || date is! Timestamp) return null;
    final loggedAt = data['loggedAt'];
    return FoodLogEntry(
      id: doc.id,
      day: date.toDate(),
      loggedAt: loggedAt is Timestamp ? loggedAt.toDate() : date.toDate(),
      foodId: foodId,
      foodName: data['foodName'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? 'g',
      grams: (data['grams'] as num?)?.toDouble() ?? 0,
      kcal: (data['kcal'] as num?)?.toInt() ?? 0,
      proteinG: (data['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (data['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (data['fatG'] as num?)?.toDouble() ?? 0,
      source: nutritionSourceFromName(data['source'] as String?),
      sourceRef: data['sourceRef'] as String? ?? '',
      origin: foodLogOriginFromName(data['origin'] as String?),
      estimated: data['estimated'] == true,
      mealId: data['mealId'] as String?,
    );
  }

  CustomFood? _customFoodFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final name = data['name'] as String?;
    final kcal = (data['kcalPer100g'] as num?)?.toDouble();
    if (name == null || name.isEmpty || kcal == null) return null;
    final createdAt = data['createdAt'];
    return CustomFood(
      id: doc.id,
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: (data['proteinPer100g'] as num?)?.toDouble() ?? 0,
      carbsPer100g: (data['carbsPer100g'] as num?)?.toDouble() ?? 0,
      fatPer100g: (data['fatPer100g'] as num?)?.toDouble() ?? 0,
      preparation: foodPreparationFromName(data['preparation'] as String?),
      portions: [
        for (final raw in (data['portions'] as List<dynamic>? ?? const []))
          if (raw is Map && raw['label'] is String && raw['grams'] is num)
            FoodPortion(
              label: raw['label'] as String,
              grams: (raw['grams'] as num).toDouble(),
            ),
      ],
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }

  DocumentReference<Map<String, dynamic>> _targetsDoc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('dietTargets')
      .doc('current');

  DocumentReference<Map<String, dynamic>> _bodyProfileDoc(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('bodyProfile')
          .doc('current');

  /// Reads a stored targets document. Returns null when the document can't be
  /// read as a real target — a missing goal, or a missing/invalid calorie
  /// figure, means "not set", never a partially-invented target.
  /// A stored body profile, or null when the document can't be read as one.
  ///
  /// Height, sex and activity are all required: two out of three cannot
  /// produce a maintenance figure, and a profile that silently defaulted the
  /// third would put a number nobody chose underneath every verdict. An
  /// implausible height is treated the same way as a missing one.
  BodyProfile? _bodyProfileFromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final heightCm = (data['heightCm'] as num?)?.toDouble();
    final sex = targetSexFromName(data['sex'] as String?);
    final activity = activityLevelFromName(data['activity'] as String?);
    if (heightCm == null || !heightIsPlausible(heightCm)) return null;
    if (sex == null || activity == null) return null;
    final stated = (data['statedMaintenanceKcal'] as num?)?.toInt();
    final updatedAt = data['updatedAt'];
    return BodyProfile(
      heightCm: heightCm,
      sex: sex,
      activity: activity,
      statedMaintenanceKcal:
          stated != null && statedMaintenanceIsPlausible(stated)
          ? stated
          : null,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }

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
/// build the same key without duplicating the format; the format itself is
/// [dietDayKey], shared with the screens.
String dayKey(DateTime day) => dietDayKey(day);
