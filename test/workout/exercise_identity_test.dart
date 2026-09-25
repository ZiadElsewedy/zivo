import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/workout/data/in_memory_exercise_library_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/analytics/plan_adherence.dart';
import 'package:zivo/features/workout/domain/exercise_history.dart';
import 'package:zivo/features/workout/domain/identity/canonical_exercise.dart';
import 'package:zivo/features/workout/domain/identity/equipment.dart';
import 'package:zivo/features/workout/domain/identity/exercise_alias.dart';
import 'package:zivo/features/workout/domain/identity/exercise_identity_resolver.dart';
import 'package:zivo/features/workout/domain/identity/exercise_matcher.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/controllers/live_session_controller.dart';

/// Exercise identity (ADR-017): one canonical exercise, many plan slots, one
/// progression history — and old records read correctly without being
/// rewritten.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('same exercise across different workout days', () {
    test('the other day\'s performance is "last time" for this one', () async {
      // Pec Deck sits on Push (slot a3) and on Chest & Back (slot c5), both
      // performing the one canonical exercise 'pec-deck'.
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        _logged(
          id: 'push-1',
          dayId: 'day-a',
          slotId: 'a3',
          exerciseId: 'pec-deck',
          kg: 55,
        ),
      );

      final c = _controller(
        day: _day('day-c', [_slot('c5', exerciseId: 'pec-deck')]),
        sessions: sessions,
      );
      addTearDown(c.dispose);
      c.start();
      await pumpEventQueue();

      final history = c.historyFor(c.session.exercises.single);
      expect(history, isNotNull);
      expect(history!.sets.single.actualWeightKg, 55);
    });

    test('adherence counts either slot as training the exercise', () {
      final plan = _plan('p1', [
        _day('day-a', [_slot('a3', exerciseId: 'pec-deck')]),
        _day('day-c', [_slot('c5', exerciseId: 'pec-deck')]),
      ]);
      final result = analyzePlanAdherence(
        plan: plan,
        sessions: [
          _logged(
            id: 's',
            dayId: 'day-c',
            slotId: 'c5',
            exerciseId: 'pec-deck',
            kg: 50,
            at: DateTime(2026, 3, 1),
          ),
        ],
        now: DateTime(2026, 3, 2),
      );
      expect(result.neglected, isEmpty);
      expect(result.plannedExerciseCount, 1);
    });
  });

  group('same exercise across different splits', () {
    test('switching splits keeps the exercise\'s history', () async {
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        _logged(
          id: 'old-split',
          planId: 'split-old',
          dayId: 'x',
          slotId: 'old-slot',
          exerciseId: 'incline-db',
          kg: 30,
        ),
      );

      final c = _controller(
        planId: 'split-new',
        day: _day('day-a', [_slot('new-slot', exerciseId: 'incline-db')]),
        sessions: sessions,
      );
      addTearDown(c.dispose);
      c.start();
      await pumpEventQueue();

      expect(
        c.historyFor(c.session.exercises.single)?.sets.single.actualWeightKg,
        30,
      );
    });
  });

  group('different equipment or variation', () {
    test('is never matched as the same exercise', () {
      final library = [
        _canonical('incline-machine', 'Incline Machine Chest Press'),
        _canonical('pulldown', 'Lat Pulldown'),
      ];
      expect(
        matchExercise(name: 'Incline Dumbbell Press', library: library).isNone,
        isTrue,
      );
      expect(
        matchExercise(
          name: 'Single-Arm Lat Pulldown (Cable)',
          library: library,
        ).isNone,
        isTrue,
        reason: 'single-arm is a different variation, not a longer name',
      );
    });

    test('keeps a separate history even with a similar name', () async {
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        _logged(
          id: 'machine',
          dayId: 'day-c',
          slotId: 'c1',
          exerciseId: 'incline-machine',
          kg: 70,
        ),
      );
      final c = _controller(
        day: _day('day-a', [
          _slot('a1', exerciseId: 'incline-db', name: 'Incline Dumbbell Press'),
        ]),
        sessions: sessions,
      );
      addTearDown(c.dispose);
      c.start();
      await pumpEventQueue();

      expect(c.historyFor(c.session.exercises.single), isNull);
    });

    test('the owner\'s real split pairs match the way a lifter would', () {
      ExerciseMatch against(String name, String other) =>
          matchExercise(name: name, library: [_canonical('x', other)]);
      // Unambiguous: same words once normalized, same (or no) equipment.
      for (final (a, b) in [
        ('Pec Deck Fly', 'Pec Deck Fly'),
        ('Cable Lateral Raises', 'Cable Lateral Raise'),
        ('Zigzag Bar Pushdown', 'EZ Bar Pushdown'),
        ('Seated Row (Wide Grip)', 'Wide-Grip Seated Row'),
        ('Rear Pec Deck', 'Rear Delt (Reverse Pec Deck)'),
      ]) {
        expect(against(a, b).confident, isNotNull, reason: '$a ≈ $b');
      }
      // Plausible: worth one question, never linked silently.
      final hammer = against('Hammer Curl', 'Hammer Dumbbell Curl');
      expect(hammer.confident, isNull);
      expect(hammer.suggestions, hasLength(1));
      // Explicit equipment beats what the name implies.
      expect(
        matchExercise(
          name: 'Incline Press',
          equipment: Equipment.dumbbell,
          library: [
            _canonical('m', 'Incline Press', equipment: Equipment.machine),
          ],
        ).isNone,
        isTrue,
      );
    });
  });

  group('renaming an exercise', () {
    test('keeps the slot\'s identity and therefore its history', () {
      const slot = PlannedExercise(
        id: 'a7',
        exerciseId: 'ez-pushdown',
        name: 'Cable Tricep Pushdown',
        order: 0,
        defaultRestSeconds: 60,
        sets: [],
      );
      final renamed = slot.copyWith(name: 'Zigzag Bar Pushdown');
      expect(renamed.id, 'a7');
      expect(renamed.canonicalId, 'ez-pushdown');

      final exercise = _canonical('ez-pushdown', 'EZ Bar Pushdown');
      final renamedExercise = exercise.copyWith(name: 'Zigzag Bar Pushdown');
      expect(renamedExercise.id, 'ez-pushdown');
    });

    test('a slot with no identity is its own exercise, by its own id', () {
      final slot = _slot('b7');
      expect(slot.exerciseId, isNull);
      expect(slot.canonicalId, 'b7');
      final started = LiveSession.start(
        _day('d', [slot]),
        id: 's',
        planId: 'p',
        now: DateTime(2026),
      );
      final e = started.exercises.single;
      expect(e.exerciseId, 'b7', reason: 'unchanged from before identities');
      expect(e.slotId, 'b7');
      expect(e.sets.first.id, 'b7-s0', reason: 'set ids unchanged too');
    });
  });

  group('legacy slot ids', () {
    test('resolve to the canonical exercise through the alias layer', () {
      final resolver = ExerciseIdentityResolver([
        _alias('c5', 'pec-deck'),
        _alias('a3', 'pec-deck'),
      ]);
      expect(resolver.canonicalIdOf('c5'), 'pec-deck');
      expect(resolver.canonicalIdOf('pec-deck'), 'pec-deck');
      expect(resolver.canonicalIdOf('unrelated'), 'unrelated');
      expect(resolver.same('a3', 'c5'), isTrue);
    });

    test('follow chains and survive a cycle without hanging', () {
      final chain = ExerciseIdentityResolver([
        _alias('a', 'b'),
        _alias('b', 'c'),
      ]);
      expect(chain.canonicalIdOf('a'), 'c');
      final cycle = ExerciseIdentityResolver([
        _alias('x', 'y'),
        _alias('y', 'x'),
      ]);
      expect(cycle.canonicalIdOf('x'), anyOf('x', 'y'));
    });

    test('canonicalize reads, never rewrites, the record', () {
      final legacy = _logged(
        id: 's',
        dayId: 'day-c',
        slotId: null,
        exerciseId: 'c5',
        instanceId: 'c5',
        kg: 50,
      );
      final resolver = ExerciseIdentityResolver([_alias('c5', 'pec-deck')]);
      final read = resolver.canonicalize([legacy]).single;
      expect(read.exercises.single.exerciseId, 'pec-deck');
      expect(read.exercises.single.effectiveSlotId, 'c5');
      expect(
        legacy.exercises.single.exerciseId,
        'c5',
        reason: 'the stored session is untouched',
      );
      expect(
        ExerciseIdentityResolver.identity.canonicalize([legacy]).single,
        same(legacy),
        reason: 'no aliases, no copies',
      );
    });

    test('a pre-identity session joins the exercise\'s history', () async {
      // Logged before identities existed: exerciseId was the slot id 'c5',
      // and no slotId was stored.
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        _logged(
          id: 'legacy',
          dayId: 'day-c',
          slotId: null,
          exerciseId: 'c5',
          instanceId: 'c5',
          kg: 52.5,
        ),
      );
      final library = InMemoryExerciseLibraryRepository();

      final c = _controller(
        day: _day('day-a', [_slot('a3', exerciseId: 'pec-deck')]),
        sessions: sessions,
        library: library,
      );
      addTearDown(c.dispose);
      c.start();
      await pumpEventQueue();
      expect(
        c.historyFor(c.session.exercises.single),
        isNull,
        reason: 'not merged yet: c5 is still its own exercise',
      );

      // The merge lands while the session is open.
      await library.saveAliases([_alias('c5', 'pec-deck')]);
      await pumpEventQueue();
      expect(
        c.historyFor(c.session.exercises.single)?.sets.single.actualWeightKg,
        52.5,
      );

      // And undoing it restores the old reading exactly.
      await library.removeAlias('c5');
      await pumpEventQueue();
      expect(c.historyFor(c.session.exercises.single), isNull);
    });
  });

  group('slot-specific goals', () {
    test(
      'the same slot\'s last performance wins over a newer one elsewhere',
      () {
        final heavyOnPush = _logged(
          id: 'push',
          dayId: 'day-a',
          slotId: 'a1',
          exerciseId: 'incline-db',
          kg: 30,
          at: DateTime(2026, 3, 1),
        );
        final pumpDay = _logged(
          id: 'chest',
          dayId: 'day-c',
          slotId: 'c3',
          exerciseId: 'incline-db',
          kg: 22.5,
          at: DateTime(2026, 3, 4),
        );
        final history = [heavyOnPush, pumpDay];

        expect(
          lastPerformanceFor(
            'incline-db',
            history,
            slotId: 'a1',
          )!.sets.single.actualWeightKg,
          30,
        );
        expect(
          lastPerformanceFor(
            'incline-db',
            history,
            slotId: 'c3',
          )!.sets.single.actualWeightKg,
          22.5,
        );
      },
    );

    test(
      'falls back to the exercise\'s wider history when the slot is new',
      () {
        final elsewhere = _logged(
          id: 'chest',
          dayId: 'day-c',
          slotId: 'c3',
          exerciseId: 'incline-db',
          kg: 22.5,
        );
        expect(
          lastPerformanceFor('incline-db', [
            elsewhere,
          ], slotId: 'brand-new')!.sets.single.actualWeightKg,
          22.5,
        );
      },
    );

    test('drives the live prefill', () async {
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        _logged(
          id: 'push',
          dayId: 'day-a',
          slotId: 'a1',
          exerciseId: 'incline-db',
          kg: 30,
          at: DateTime(2026, 3, 1),
        ),
      );
      await sessions.saveSession(
        _logged(
          id: 'chest',
          dayId: 'day-c',
          slotId: 'c3',
          exerciseId: 'incline-db',
          kg: 22.5,
          at: DateTime(2026, 3, 4),
        ),
      );
      final c = _controller(
        day: _day('day-a', [_slot('a1', exerciseId: 'incline-db')]),
        sessions: sessions,
      );
      addTearDown(c.dispose);
      c.start();
      await pumpEventQueue();
      c.endWarmup();

      expect(
        c.historyFor(c.session.exercises.single)?.sets.single.actualWeightKg,
        30,
      );
      expect(
        c
            .previousSetFor(
              c.session.exercises.single,
              c.session.exercises.single.sets.first,
            )
            ?.actualWeightKg,
        30,
      );
    });
  });
}

// ---- Fixtures ---------------------------------------------------------------

PlannedExercise _slot(String id, {String? exerciseId, String name = 'Lift'}) =>
    PlannedExercise(
      id: id,
      exerciseId: exerciseId,
      name: name,
      order: 0,
      defaultRestSeconds: 90,
      sets: const [
        PlannedSet(
          order: 0,
          repTarget: RepTarget.fixed(8),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
    );

WorkoutDay _day(String id, List<PlannedExercise> exercises) =>
    WorkoutDay(id: id, slot: id, label: id, order: 0, exercises: exercises);

WorkoutPlan _plan(String id, List<WorkoutDay> days) => WorkoutPlan(
  id: id,
  name: id,
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  cycleCursor: 0,
  days: days,
);

/// A completed session with one exercise and one done set of 8 × [kg].
/// [slotId] null + [instanceId] models a record written before slots were
/// stored, where the instance id WAS the slot id.
LiveSession _logged({
  required String id,
  String planId = 'p1',
  required String dayId,
  required String? slotId,
  required String exerciseId,
  String? instanceId,
  required double kg,
  DateTime? at,
}) {
  final when = at ?? DateTime(2026, 2, 1, 9);
  return LiveSession(
    id: id,
    planId: planId,
    dayId: dayId,
    dayLabel: dayId,
    startedAt: when,
    completedAt: when.add(const Duration(hours: 1)),
    status: SessionStatus.completed,
    exercises: [
      SessionExercise(
        id: instanceId ?? slotId ?? exerciseId,
        exerciseId: exerciseId,
        slotId: slotId,
        name: 'Lift',
        restSeconds: 90,
        sets: [
          LoggedSet(
            id: '$id-s0',
            target: const RepTarget.fixed(8),
            outcome: SetOutcome.completed,
            actualReps: 8,
            actualWeightKg: kg,
            resolvedAt: when,
          ),
        ],
      ),
    ],
  );
}

CanonicalExercise _canonical(String id, String name, {Equipment? equipment}) =>
    CanonicalExercise(
      id: id,
      name: name,
      equipment: equipment,
      createdAt: DateTime(2026),
    );

ExerciseAlias _alias(String legacyId, String canonicalId) => ExerciseAlias(
  legacyId: legacyId,
  canonicalId: canonicalId,
  source: AliasSource.merge,
  createdAt: DateTime(2026),
);

LiveSessionController _controller({
  required WorkoutDay day,
  required InMemoryWorkoutSessionRepository sessions,
  String planId = 'p1',
  InMemoryExerciseLibraryRepository? library,
}) => LiveSessionController(
  day: day,
  plan: _plan(planId, [day]),
  sessions: sessions,
  exerciseLibrary: library,
  vsync: _NoopTickerProvider(),
  now: () => DateTime(2026, 3, 10, 10),
);

class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
