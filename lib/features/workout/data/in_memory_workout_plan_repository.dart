import 'dart:async';

import '../domain/workout_plan.dart';
import '../domain/workout_plan_normalize.dart';
import '../domain/workout_plan_repository.dart';
import 'ziad_workout_plan.dart';

/// Demo store: one active workout plan, in memory, broadcasting changes.
/// Seeded with the owner's real ingested split ([ziadWorkoutPlan]) so the page
/// opens on the actual source-of-truth plan.
class InMemoryWorkoutPlanRepository implements WorkoutPlanRepository {
  InMemoryWorkoutPlanRepository() {
    _plan = ziadWorkoutPlan();
  }

  WorkoutPlan? _plan;

  final StreamController<WorkoutPlan?> _planController =
      StreamController<WorkoutPlan?>.broadcast();

  @override
  WorkoutPlan? get activePlan => _plan;

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    yield activePlan;
    yield* _planController.stream;
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    _plan = normalizeWorkoutPlanOrder(plan);
    _planController.add(_plan);
  }

  @override
  Future<void> deletePlan(String id) async {
    if (_plan?.id != id) return;
    _plan = null;
    _planController.add(_plan);
  }

  void dispose() {
    _planController.close();
  }
}
