import 'dart:async';

import '../domain/workout_plan.dart';
import '../domain/workout_plan_normalize.dart';
import '../domain/workout_plan_repository.dart';
import '../domain/workout_plan_status.dart';
import 'ziad_workout_plan.dart';

/// Demo store: many workout splits in memory, with at most one active, and
/// broadcasting changes. Seeded with the owner's real ingested split
/// ([ziadWorkoutPlan]) as the active one, so the page opens on the actual
/// source-of-truth plan.
class InMemoryWorkoutPlanRepository implements WorkoutPlanRepository {
  InMemoryWorkoutPlanRepository() {
    final seed = ziadWorkoutPlan();
    _splits = [seed];
    _activeId = seed.id;
  }

  late final List<WorkoutPlan> _splits;
  String? _activeId;

  final StreamController<WorkoutPlan?> _activeController =
      StreamController<WorkoutPlan?>.broadcast();
  final StreamController<List<WorkoutPlan>> _splitsController =
      StreamController<List<WorkoutPlan>>.broadcast();

  // --- Back-compat facade over the active split ---

  @override
  WorkoutPlan? get activePlan => _resolveActive();

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    yield _resolveActive();
    yield* _activeController.stream;
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    // Back-compat: the single-plan API always made the saved plan THE active
    // plan (the old impl replaced its one slot; every test double sets
    // `_active = plan`). Preserve that — save/replace by id, then point active
    // at it. (saveSplit, the new multi-split API, does NOT steal active.)
    final normalized = normalizeWorkoutPlanOrder(plan);
    final index = _splits.indexWhere((s) => s.id == normalized.id);
    if (index >= 0) {
      _splits[index] = normalized;
    } else {
      _splits.add(normalized);
    }
    _activeId = normalized.id;
    _emitActive();
    _emitSplits();
  }

  @override
  Future<void> deletePlan(String id) => deleteSplit(id);

  // --- Multi-split API ---

  @override
  List<WorkoutPlan> get splits => List.unmodifiable(_sorted());

  @override
  Stream<List<WorkoutPlan>> watchSplits() async* {
    yield List.unmodifiable(_sorted());
    yield* _splitsController.stream;
  }

  @override
  String? get activeSplitId => _resolveActive()?.id;

  @override
  Future<void> setActiveSplit(String id) async {
    final exists = _splits.any((s) => s.id == id);
    if (!exists) {
      throw StateError('setActiveSplit: no split with id "$id".');
    }
    _activeId = id;
    _emitActive();
    _emitSplits();
  }

  @override
  Future<void> saveSplit(WorkoutPlan plan) async {
    final normalized = normalizeWorkoutPlanOrder(plan);
    final index = _splits.indexWhere((s) => s.id == normalized.id);
    if (index >= 0) {
      _splits[index] = normalized;
    } else {
      _splits.add(normalized);
    }
    // First split ever saved (no active pointer yet) becomes active.
    _activeId ??= normalized.id;
    _emitActive();
    _emitSplits();
  }

  @override
  Future<void> deleteSplit(String id) async {
    final removed = _splits.indexWhere((s) => s.id == id) >= 0;
    if (!removed) return;
    _splits.removeWhere((s) => s.id == id);
    if (_activeId == id) {
      final remaining = _sorted();
      _activeId = remaining.isEmpty ? null : remaining.first.id;
    }
    _emitActive();
    _emitSplits();
  }

  void dispose() {
    _activeController.close();
    _splitsController.close();
  }

  // --- Internals ---

  /// Splits in createdAt (ascending) order — stable, id-tiebroken.
  List<WorkoutPlan> _sorted() {
    final copy = List<WorkoutPlan>.of(_splits);
    copy.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return copy;
  }

  /// The active split: the one whose id == [_activeId]; falling back (for
  /// back-compat when no pointer is set) to the OLDEST `active`-status split
  /// (createdAt order — [_sorted] is ascending), then the oldest split overall,
  /// then null. Deliberately the same "oldest wins a tie" convention
  /// [deleteSplit] already uses when repointing after the active split is
  /// removed — not an accident of iteration order.
  WorkoutPlan? _resolveActive() {
    if (_splits.isEmpty) return null;
    if (_activeId != null) {
      for (final s in _splits) {
        if (s.id == _activeId) return s;
      }
    }
    final sorted = _sorted();
    for (final s in sorted) {
      if (s.status == WorkoutPlanStatus.active) return s;
    }
    return sorted.first;
  }

  void _emitActive() => _activeController.add(_resolveActive());

  void _emitSplits() => _splitsController.add(List.unmodifiable(_sorted()));
}
