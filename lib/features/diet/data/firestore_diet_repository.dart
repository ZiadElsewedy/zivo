import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/diet_day.dart';
import '../domain/diet_plan.dart';
import '../domain/diet_plan_status.dart';
import '../domain/diet_repository.dart';
import '../domain/diet_source.dart';
import '../domain/food_item.dart';
import '../domain/meal.dart';

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
class FirestoreDietRepository implements DietRepository {
  FirestoreDietRepository({FirebaseFirestore? firestore, required this.uidSource})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  DietPlan? _activePlan;
  StreamController<DietPlan?>? _planController;
  StreamSubscription<String?>? _planUidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _planQuerySub;

  @override
  DietPlan? get activePlan => _activePlan;

  @override
  Stream<DietPlan?> watchActivePlan() {
    return (_planController ??= StreamController<DietPlan?>.broadcast(
      onListen: _startPlan,
      onCancel: _stopPlan,
    )).stream;
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
        });
  }

  DietPlan? _firstActive(List<DietPlan> plans) {
    for (final plan in plans) {
      if (plan.status == DietPlanStatus.active) return plan;
    }
    return null;
  }

  void _emitPlan(DietPlan? plan) {
    _activePlan = plan;
    _planController?.add(_activePlan);
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
          });
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
