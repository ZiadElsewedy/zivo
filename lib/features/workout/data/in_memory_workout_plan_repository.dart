import 'dart:async';

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

/// Demo store: one active workout plan, in memory, broadcasting changes.
/// Seeded with a rotating 3-day Push/Pull/Legs cycle so the page opens with
/// something to show.
class InMemoryWorkoutPlanRepository implements WorkoutPlanRepository {
  InMemoryWorkoutPlanRepository() {
    _plan = _seedPlan();
  }

  WorkoutPlan? _plan;

  final StreamController<WorkoutPlan?> _planController =
      StreamController<WorkoutPlan?>.broadcast();

  WorkoutPlan _seedPlan() {
    final now = DateTime.now();
    return WorkoutPlan(
      id: 'seed-plan-1',
      name: 'Push / Pull / Legs',
      status: WorkoutPlanStatus.active,
      source: WorkoutPlanSource.manual,
      createdAt: now,
      updatedAt: now,
      cycleCursor: 0,
      days: const [
        WorkoutDay(
          id: 'seed-day-a',
          slot: 'A',
          label: 'Push',
          order: 0,
          exercises: [
            PlannedExercise(
              id: 'seed-ex-bench',
              name: 'Bench Press',
              order: 0,
              muscleGroup: 'Chest',
              defaultRestSeconds: 120,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.fixed(10),
                  restSeconds: 90,
                  type: SetType.warmup,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 120,
                  targetWeightKg: 60,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 120,
                  targetWeightKg: 60,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 3,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 120,
                  targetWeightKg: 60,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-ohp',
              name: 'Overhead Press',
              order: 1,
              muscleGroup: 'Shoulders',
              defaultRestSeconds: 90,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 90,
                  targetWeightKg: 32.5,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 90,
                  targetWeightKg: 32.5,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 90,
                  targetWeightKg: 32.5,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-lateral-raise',
              name: 'Lateral Raise',
              order: 2,
              muscleGroup: 'Shoulders',
              defaultRestSeconds: 60,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.fixed(15),
                  restSeconds: 60,
                  targetWeightKg: 8,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.fixed(15),
                  restSeconds: 60,
                  targetWeightKg: 8,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.fixed(15),
                  restSeconds: 60,
                  targetWeightKg: 8,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-triceps-pushdown',
              name: 'Triceps Pushdown',
              order: 3,
              muscleGroup: 'Triceps',
              defaultRestSeconds: 60,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.toFailure(),
                  restSeconds: 60,
                  type: SetType.failure,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.toFailure(),
                  restSeconds: 60,
                  type: SetType.failure,
                ),
              ],
            ),
          ],
        ),
        WorkoutDay(
          id: 'seed-day-b',
          slot: 'B',
          label: 'Pull',
          order: 1,
          exercises: [
            PlannedExercise(
              id: 'seed-ex-deadlift',
              name: 'Deadlift',
              order: 0,
              muscleGroup: 'Back',
              defaultRestSeconds: 180,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.fixed(5),
                  restSeconds: 180,
                  targetWeightKg: 100,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.fixed(5),
                  restSeconds: 180,
                  targetWeightKg: 100,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.fixed(5),
                  restSeconds: 180,
                  targetWeightKg: 100,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-barbell-row',
              name: 'Barbell Row',
              order: 1,
              muscleGroup: 'Back',
              defaultRestSeconds: 120,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 50,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 50,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 50,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-lat-pulldown',
              name: 'Lat Pulldown',
              order: 2,
              muscleGroup: 'Back',
              defaultRestSeconds: 90,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-face-pull',
              name: 'Face Pull',
              order: 3,
              muscleGroup: 'Rear delts',
              defaultRestSeconds: 60,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.fixed(15),
                  restSeconds: 60,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.fixed(15),
                  restSeconds: 60,
                  type: SetType.working,
                ),
              ],
            ),
          ],
        ),
        WorkoutDay(
          id: 'seed-day-c',
          slot: 'C',
          label: 'Legs',
          order: 2,
          exercises: [
            PlannedExercise(
              id: 'seed-ex-squat',
              name: 'Back Squat',
              order: 0,
              muscleGroup: 'Quads',
              defaultRestSeconds: 150,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.fixed(10),
                  restSeconds: 90,
                  type: SetType.warmup,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 150,
                  targetWeightKg: 80,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 150,
                  targetWeightKg: 80,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 3,
                  repTarget: RepTarget.range(6, 8),
                  restSeconds: 150,
                  targetWeightKg: 80,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-rdl',
              name: 'Romanian Deadlift',
              order: 1,
              muscleGroup: 'Hamstrings',
              defaultRestSeconds: 120,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 70,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 70,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(8, 10),
                  restSeconds: 120,
                  targetWeightKg: 70,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-leg-press',
              name: 'Leg Press',
              order: 2,
              muscleGroup: 'Quads',
              defaultRestSeconds: 90,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  targetWeightKg: 140,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  targetWeightKg: 140,
                  type: SetType.working,
                ),
                PlannedSet(
                  order: 2,
                  repTarget: RepTarget.range(10, 12),
                  restSeconds: 90,
                  targetWeightKg: 140,
                  type: SetType.working,
                ),
              ],
            ),
            PlannedExercise(
              id: 'seed-ex-calf-raise',
              name: 'Calf Raise',
              order: 3,
              muscleGroup: 'Calves',
              defaultRestSeconds: 60,
              sets: [
                PlannedSet(
                  order: 0,
                  repTarget: RepTarget.toFailure(),
                  restSeconds: 60,
                  type: SetType.failure,
                ),
                PlannedSet(
                  order: 1,
                  repTarget: RepTarget.toFailure(),
                  restSeconds: 60,
                  type: SetType.failure,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

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
