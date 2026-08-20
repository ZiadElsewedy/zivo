import '../../ai/domain/workout_import_result.dart';
import 'planned_exercise.dart';
import 'rep_target.dart';
import 'set_type.dart';
import 'workout_day.dart';
import 'workout_plan.dart';
import 'workout_plan_source.dart';
import 'workout_plan_status.dart';
import 'workout_set.dart';

/// Converts an AI-extracted [WorkoutImportResult] (WORKOUT_SYSTEM.md §3.4,
/// Phase 6) into a real, editable [WorkoutPlan] draft — with freshly-minted
/// ids for the plan/days/exercises, so the result is a genuinely new split
/// the moment it's saved (never collides with an existing one). [source] is
/// always [WorkoutPlanSource.pdf], the marker reserved for exactly this.
///
/// This produces a DRAFT for review, not a saved split — the caller pushes
/// it into `WorkoutPlanEditPage(initialPlan: ..., asSplit: true)` so the user
/// can fix anything before tapping Save; nothing here touches
/// `WorkoutPlanRepository`.
WorkoutPlan workoutPlanFromImport(WorkoutImportResult result, {required String id, required DateTime now}) {
  final days = <WorkoutDay>[];
  for (var i = 0; i < result.days.length; i++) {
    final importedDay = result.days[i];
    final dayId = '$id-d$i';
    final exercises = <PlannedExercise>[];
    for (var j = 0; j < importedDay.exercises.length; j++) {
      exercises.add(_plannedExerciseFrom(importedDay.exercises[j], id: '$dayId-e$j', order: j));
    }
    days.add(
      WorkoutDay(
        id: dayId,
        slot: importedDay.slot.isEmpty ? _slotForIndex(i) : importedDay.slot,
        label: importedDay.label,
        order: i,
        exercises: exercises,
      ),
    );
  }

  return WorkoutPlan(
    id: id,
    name: result.planName,
    status: WorkoutPlanStatus.active,
    source: WorkoutPlanSource.pdf,
    createdAt: now,
    updatedAt: now,
    cycleCursor: 0,
    days: days,
  );
}

PlannedExercise _plannedExerciseFrom(ImportedExercise exercise, {required String id, required int order}) {
  final rest = exercise.restSeconds ?? 90;
  final target = _repTargetFrom(exercise);
  final setCount = exercise.sets < 1 ? 1 : exercise.sets;
  return PlannedExercise(
    id: id,
    name: exercise.name,
    order: order,
    muscleGroup: exercise.muscleGroup,
    defaultRestSeconds: rest,
    sets: [
      for (var s = 0; s < setCount; s++)
        PlannedSet(
          order: s,
          repTarget: target,
          restSeconds: rest,
          targetWeightKg: exercise.targetWeightKg,
          type: SetType.working,
        ),
    ],
  );
}

RepTarget _repTargetFrom(ImportedExercise exercise) {
  if (exercise.toFailure) return const RepTarget.toFailure();
  final min = exercise.repsMin;
  final max = exercise.repsMax;
  if (min != null && max != null && min != max) return RepTarget.range(min, max);
  return RepTarget.fixed(min ?? max ?? 8);
}

/// A, B, C… — the fallback slot letter when the extraction left one blank.
String _slotForIndex(int index) => index < 26 ? String.fromCharCode(0x41 + index) : '${index + 1}';
