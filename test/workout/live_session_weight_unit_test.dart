import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/weight_unit.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/presentation/controllers/live_session_controller.dart';

/// The controller half of the KG/LB feature: the weight field is shown/typed in
/// the active unit, but only ever *stored* in kilograms. These pin that the
/// conversion happens at exactly the read/write boundary and that the unit is a
/// persisted device preference.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to kg; typing kg stores kg unchanged', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    expect(c.weightUnit, WeightUnit.kg);
    c.reps.text = '6';
    c.weight.text = '72.5';
    c.setDone(reducedMotion: true);

    expect(c.session.exercises.first.sets.first.actualWeightKg, 72.5);
  });

  test('switching to lb re-expresses the field in place without a re-log', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.weight.text = '72.5'; // kg
    c.setUnit(WeightUnit.lb);

    // 72.5 kg → 159.83 lb → snapped to "160".
    expect(c.weight.text, '160');
    // Nothing has been logged yet — a unit switch is a change of view, not input.
    expect(c.session.exercises.first.sets.first.actualWeightKg, isNull);
  });

  test('entering a load in lb stores canonical kilograms', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.setUnit(WeightUnit.lb);
    c.reps.text = '6';
    c.weight.text = '190'; // lb
    c.setDone(reducedMotion: true);

    final logged = c.session.exercises.first.sets.first;
    expect(logged.actualReps, 6);
    expect(logged.actualWeightKg, closeTo(86.1826, 1e-3));
  });

  test('typedWeightKg converts the field back to kg at the read boundary', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.weight.text = '72.5';
    expect(c.typedWeightKg, 72.5);

    c.setUnit(WeightUnit.lb);
    c.weight.text = '190';
    expect(c.typedWeightKg, closeTo(86.1826, 1e-3));
  });

  test('the unit is a persisted preference a fresh session restores', () async {
    final first = _controller();
    addTearDown(first.dispose);
    first.start();
    await _settle(); // let start's own (empty) preference read land first
    first.setUnit(WeightUnit.lb);
    await _settle(); // let the write reach SharedPreferences

    // A new controller (same device prefs) loads lb asynchronously on start.
    final second = _controller();
    addTearDown(second.dispose);
    second.start();
    await _settle();

    expect(second.weightUnit, WeightUnit.lb);
  });

  test('a lb-restored session prefills its suggestion in lb', () async {
    SharedPreferences.setMockInitialValues({
      'zivo.session.weightUnit': 'lb',
    });
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    await _settle();
    c.endWarmup();

    // The plan prescribes 60 kg; in lb that is 132.28 → snapped to "132.5".
    expect(c.weightUnit, WeightUnit.lb);
    expect(c.weight.text, WeightUnit.lb.display(60));
  });
}

/// Lets the unawaited SharedPreferences read in [LiveSessionController.start]
/// resolve.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

LiveSessionController _controller() {
  final day = _day();
  return LiveSessionController(
    day: day,
    plan: _plan(day),
    sessions: InMemoryWorkoutSessionRepository(),
    vsync: _NoopTickerProvider(),
    now: () => DateTime(2026, 3, 1, 10),
  );
}

WorkoutDay _day() => const WorkoutDay(
  id: 'a',
  slot: 'A',
  label: 'Push',
  order: 0,
  exercises: [
    PlannedExercise(
      id: 'ex1',
      name: 'Bench',
      order: 0,
      muscleGroup: 'Chest',
      defaultRestSeconds: 90,
      sets: [
        PlannedSet(
          order: 0,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
          targetWeightKg: 60,
        ),
      ],
    ),
  ],
);

WorkoutPlan _plan(WorkoutDay day) => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: [day],
);

class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
