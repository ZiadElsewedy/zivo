import '../domain/planned_exercise.dart';
import '../domain/rep_target.dart';
import '../domain/set_type.dart';
import '../domain/workout_day.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_plan_source.dart';
import '../domain/workout_plan_status.dart';
import '../domain/workout_set.dart';

/// The owner's actual training split, ingested from their PDF
/// ("ziad el sewedy — Push/Pull/Rest/Arnold's split"). This is the real
/// source-of-truth plan the app opens with, superseding the earlier PPL demo.
///
/// Ingestion decisions (owner-approved):
/// - Rest days are NOT modeled — the cycle simply advances on the next training
///   day (owner's rotating-cycle rule, not weekday-bound). So the plan is a
///   5-day rotation A→B→C→D→E.
/// - The PDF's blank Current/Goal weight fields carry no load, so no set has a
///   target weight yet — the user fills those in-app.
/// - The abs block is intentionally left out of the day plans (done separately).
/// - Rest defaults (the PDF gives none): [_restStrength] for the 8–10 rep sets,
///   [_restLight] for the higher-rep (15) and to-failure sets.
/// - Names are lightly tidied and the two lumped entries
///   ("Leg Press + Standing Calf Raise", "Adductor × Abductor") are split.
///
/// [source] is [WorkoutPlanSource.pdf] — the marker reserved for exactly this.

const int _restStrength = 90; // 8–10 rep working sets
const int _restLight = 60; // 15-rep and to-failure sets

final RepTarget _hypertrophy = const RepTarget.range(8, 10);
final RepTarget _fifteen = const RepTarget.fixed(15);
final RepTarget _toFailure = const RepTarget.toFailure();

/// Builds one exercise: [sets] identical sets of [target], resting [rest]
/// seconds between them. [order] is reassigned by [_day].
PlannedExercise _ex(
  String id,
  String name, {
  required int sets,
  required RepTarget target,
  required int rest,
  SetType type = SetType.working,
}) => PlannedExercise(
  id: id,
  name: name,
  order: 0,
  defaultRestSeconds: rest,
  sets: [
    for (var i = 0; i < sets; i++)
      PlannedSet(order: i, repTarget: target, restSeconds: rest, type: type),
  ],
);

/// Builds one day, reindexing its exercises to contiguous 0-based order.
WorkoutDay _day(String id, String slot, String label, List<PlannedExercise> exercises) => WorkoutDay(
  id: id,
  slot: slot,
  label: label,
  order: 0,
  exercises: [for (var i = 0; i < exercises.length; i++) exercises[i].copyWith(order: i)],
);

/// The ingested plan.
WorkoutPlan ziadWorkoutPlan() {
  final now = DateTime.now();
  final rawDays = <WorkoutDay>[
    _day('day-a', 'A', 'Push', [
      _ex('a1', 'Incline Dumbbell Press', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('a2', 'Flat Chest Press Machine', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('a3', 'Pec Deck Fly', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('a4', 'Cable Lateral Raises', sets: 3, target: _hypertrophy, rest: _restStrength),
      _ex('a5', 'Shoulder Press Machine', sets: 1, target: _hypertrophy, rest: _restStrength),
      _ex('a6', 'Overhead Single-Arm Press', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('a7', 'Zigzag Bar Pushdown', sets: 2, target: _hypertrophy, rest: _restStrength),
    ]),
    _day('day-b', 'B', 'Pull', [
      _ex('b1', 'Lat Pulldown', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b2', 'Seated Row (Wide Grip)', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b3', 'Seated Row (Single Arm)', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b4', 'Hip Extension', sets: 2, target: _toFailure, rest: _restLight, type: SetType.failure),
      _ex('b5', 'Incline Dumbbell Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b6', 'Hammer Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b7', 'Preacher Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('b8', 'Rear Pec Deck', sets: 2, target: _hypertrophy, rest: _restStrength),
    ]),
    _day('day-c', 'C', 'Chest & Back', [
      _ex('c1', 'Incline Machine Chest Press', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('c2', 'Single-Arm Lat Pulldown (Cable)', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('c3', 'Dumbbell Chest Press', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('c4', 'Wide-Grip Seated Row', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('c5', 'Pec Deck Fly', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('c6', 'Pullover', sets: 2, target: _hypertrophy, rest: _restStrength),
    ]),
    _day('day-d', 'D', 'Full Arm', [
      _ex('d1', 'Cable Lateral Raise', sets: 3, target: _hypertrophy, rest: _restStrength),
      _ex('d2', 'Rear Delt (Reverse Pec Deck)', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('d3', 'Face-Away Cable Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('d4', 'Hammer Dumbbell Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('d5', 'Preacher Curl', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('d6', 'Overhead Cable Single-Arm Extension', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('d7', 'EZ Bar Pushdown', sets: 2, target: _hypertrophy, rest: _restStrength),
    ]),
    _day('day-e', 'E', 'Legs', [
      _ex('e1', 'Hack Squat', sets: 3, target: _hypertrophy, rest: _restStrength),
      _ex('e2', 'Leg Extensions', sets: 3, target: _hypertrophy, rest: _restStrength),
      _ex('e3', 'Seated Leg Curl', sets: 3, target: _hypertrophy, rest: _restStrength),
      _ex('e4', 'Dumbbell Romanian Deadlift', sets: 2, target: _hypertrophy, rest: _restStrength),
      _ex('e5', 'Adductor', sets: 3, target: _fifteen, rest: _restLight),
      _ex('e6', 'Abductor', sets: 3, target: _fifteen, rest: _restLight),
      _ex('e7', 'Leg Press', sets: 3, target: _fifteen, rest: _restLight),
      _ex('e8', 'Standing Calf Raise', sets: 3, target: _fifteen, rest: _restLight),
    ]),
  ];
  // Reindex days to contiguous 0-based order (the rotation position).
  final days = [for (var i = 0; i < rawDays.length; i++) rawDays[i].copyWith(order: i)];

  return WorkoutPlan(
    id: 'ziad-arnold-split',
    name: 'Push · Pull · Arnold Split',
    status: WorkoutPlanStatus.active,
    source: WorkoutPlanSource.pdf,
    createdAt: now,
    updatedAt: now,
    cycleCursor: 0,
    days: days,
  );
}
