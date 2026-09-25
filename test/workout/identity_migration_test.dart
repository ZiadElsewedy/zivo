import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_exercise_library_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/exercise_history.dart';
import 'package:zivo/features/workout/domain/identity/canonical_exercise.dart';
import 'package:zivo/features/workout/domain/identity/exercise_alias.dart';
import 'package:zivo/features/workout/domain/identity/exercise_identity_resolver.dart';
import 'package:zivo/features/workout/domain/identity/exercise_identity_sync.dart';
import 'package:zivo/features/workout/domain/identity/exercise_library_repository.dart';
import 'package:zivo/features/workout/domain/identity/exercise_choice.dart';
import 'package:zivo/features/workout/domain/identity/exercise_matcher.dart';
import 'package:zivo/features/workout/domain/identity/exercise_merge.dart';
import 'package:zivo/features/workout/domain/identity/equipment.dart';
import 'package:zivo/features/workout/domain/identity/identity_reconcile.dart';
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

/// The identity migration (ADR-017): every legacy id gets a canonical
/// identity, the same movement across days and splits becomes one, different
/// variations and equipment stay apart — and no logged session is touched.
void main() {
  _mergeTests();
  _planEditTests();

  final now = DateTime(2026, 9, 25, 12);

  group('reconcileExerciseIdentities', () {
    test("the owner's repeated movements merge across days, however they "
        'were spelled', () {
      final r = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: const [],
        library: ExerciseLibrary(),
        now: now,
      );
      final id = r.slotIdentities;
      expect(id['a-pec'], id['b-pec']);
      expect(id['a-preacher'], id['b-preacher']);
      expect(id['a-lat'], id['b-lat'], reason: 'Raise ≈ Raises');
      expect(id['a-push'], id['b-push'], reason: 'Zigzag ≈ EZ');
      expect(id['a-row'], id['b-row'], reason: 'word order');
      expect(id['a-hammer'], id['b-hammer']);
      expect(id['a-rear'], id['b-rear'], reason: 'rear ≈ reverse pec deck');
      // 7 shared movements + 2 that must stay apart = 9 identities.
      expect(r.exercises, hasLength(9));
    });

    test('different equipment or variation is never merged', () {
      final r = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: const [],
        library: ExerciseLibrary(),
        now: now,
      );
      expect(
        r.slotIdentities['a-incline-db'],
        isNot(r.slotIdentities['b-incline-machine']),
      );
    });

    test('every slot is aliased, so its old sessions follow it', () {
      final r = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: const [],
        library: ExerciseLibrary(),
        now: now,
      );
      final aliased = {for (final a in r.aliases) a.legacyId: a.canonicalId};
      for (final entry in r.slotIdentities.entries) {
        expect(aliased[entry.key], entry.value);
      }
      expect(r.aliases.every((a) => a.source == AliasSource.migration), isTrue);
      expect(
        r.exercises.every((e) => isCanonicalExerciseId(e.id)),
        isTrue,
        reason: 'a canonical id never collides with a slot id',
      );
    });

    test('ids are deterministic — two devices write the same documents', () {
      ExerciseLibrary lib() => ExerciseLibrary();
      final a = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: const [],
        library: lib(),
        now: now,
      );
      final b = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: const [],
        library: lib(),
        now: now.add(const Duration(hours: 1)),
      );
      expect(a.slotIdentities, b.slotIdentities);
      expect(a.exercises.map((e) => e.id), b.exercises.map((e) => e.id));
    });

    test('running it again on its own output finds nothing to do', () {
      final split = _ownerSplit();
      final sessions = [_session('s1', 'a-pec', 'Pec Deck', DateTime(2026, 9))];
      final first = reconcileExerciseIdentities(
        splits: [split],
        sessions: sessions,
        library: ExerciseLibrary(),
        now: now,
      );
      final after = ExerciseLibrary(
        exercises: {for (final e in first.exercises) e.id: e},
        aliases: first.aliases,
      );
      final second = reconcileExerciseIdentities(
        splits: [applySlotIdentities(split, first.slotIdentities)],
        sessions: sessions,
        library: after,
        now: now,
      );
      expect(second.isEmpty, isTrue);
    });

    test('an id only history remembers (a deleted split) joins by name', () {
      final r = reconcileExerciseIdentities(
        splits: [_ownerSplit()],
        sessions: [
          _session('old', 'gone-split-e3', 'Preacher Curls', DateTime(2026, 5)),
        ],
        library: ExerciseLibrary(),
        now: now,
      );
      final alias = r.aliases.firstWhere((a) => a.legacyId == 'gone-split-e3');
      expect(alias.canonicalId, r.slotIdentities['a-preacher']);
    });

    test('a canonical id missing its document gets one, not an alias', () {
      final r = reconcileExerciseIdentities(
        splits: const [],
        sessions: [_session('s', 'x-abc1', 'Machine Press', DateTime(2026, 9))],
        library: ExerciseLibrary(),
        now: now,
      );
      expect(r.exercises.single.id, 'x-abc1');
      expect(r.aliases, isEmpty);
    });

    test('a slot the editor already linked is left alone; its missing '
        'exercise is created under the id it uses', () {
      final split = _split('p', [
        _day('d', [_slot('s1', 'Bench Press', exerciseId: 'x-bench')]),
      ]);
      final r = reconcileExerciseIdentities(
        splits: [split],
        sessions: const [],
        library: ExerciseLibrary(),
        now: now,
      );
      expect(r.slotIdentities, isEmpty);
      expect(r.aliases, isEmpty);
      expect(r.exercises.single.id, 'x-bench');
    });

    test('a new slot matching an existing library exercise links to it', () {
      final library = ExerciseLibrary(
        exercises: {
          'x-lat': CanonicalExercise(
            id: 'x-lat',
            name: 'Lat Pulldown',
            createdAt: DateTime(2026),
          ),
        },
      );
      final r = reconcileExerciseIdentities(
        splits: [
          _split('p', [
            _day('d', [_slot('new-1', 'lat pull down')]),
          ]),
        ],
        sessions: const [],
        library: library,
        now: now,
      );
      expect(r.slotIdentities['new-1'], 'x-lat');
      expect(r.exercises, isEmpty);
    });
  });

  group('shared history after migration', () {
    test("Day B's slot reads Day A's session as its last time — without the "
        'session being rewritten', () {
      final split = _ownerSplit();
      final session = _session('s1', 'a-pec', 'Pec Deck', DateTime(2026, 9, 1));
      final r = reconcileExerciseIdentities(
        splits: [split],
        sessions: [session],
        library: ExerciseLibrary(),
        now: now,
      );
      final resolver = ExerciseIdentityResolver(r.aliases);
      final history = lastPerformanceFor(
        r.slotIdentities['b-pec']!,
        resolver.canonicalize([session]),
        slotId: 'b-pec',
      );
      expect(history, isNotNull);
      expect(history!.topWeightKg, 50);
      expect(session.exercises.single.exerciseId, 'a-pec');
    });
  });

  group('ExerciseIdentitySync', () {
    test('migrates an account end to end and never touches a session', () async {
      final plans = await _plansWith(_ownerSplit());
      addTearDown(plans.dispose);
      final sessions = InMemoryWorkoutSessionRepository();
      final logged = _session('s1', 'a-row', 'Wide-Grip Seated Row', DateTime(2026, 9));
      await sessions.saveSession(logged);
      final library = InMemoryExerciseLibraryRepository();
      addTearDown(library.dispose);

      final sync = ExerciseIdentitySync(
        plans: plans,
        sessions: sessions,
        library: library,
        now: () => now,
      );
      final result = await sync.run();

      expect(result.isEmpty, isFalse);
      final slots = [
        for (final d in plans.splits.single.days) ...d.exercises,
      ];
      expect(slots.every((s) => s.exerciseId != null), isTrue);
      expect(library.current.exercises, hasLength(9));
      expect(
        identical(sessions.current.single, logged) ||
            sessions.current.single.exercises.single.exerciseId == 'a-row',
        isTrue,
        reason: 'history is read through aliases, never rewritten',
      );
      final second = await sync.run();
      expect(second.isEmpty, isTrue);
    });

    test('waits for the library to load rather than minting duplicates', () async {
      final plans = await _plansWith(_ownerSplit());
      addTearDown(plans.dispose);
      final library = _NeverLoadedLibrary();
      final sync = ExerciseIdentitySync(
        plans: plans,
        sessions: InMemoryWorkoutSessionRepository(),
        library: library,
        loadTimeout: const Duration(milliseconds: 10),
      );
      final result = await sync.run();
      expect(result.isEmpty, isTrue);
      expect(library.saved, isEmpty);
      expect(
        plans.splits.single.days.first.exercises.first.exerciseId,
        isNull,
      );
    });

    test('never overwrites an identity a slot already has', () {
      final split = _split('p', [
        _day('d', [_slot('s1', 'Bench', exerciseId: 'x-mine')]),
      ]);
      final linked = applySlotIdentities(split, {'s1': 'x-other'});
      expect(identical(linked, split), isTrue);
    });
  });
}

void _mergeTests() {
  CanonicalExercise ex(String id, String name, {Equipment? eq, int year = 2026}) =>
      CanonicalExercise(id: id, name: name, equipment: eq, createdAt: DateTime(year));

  group('suggestExerciseMerges ("Same exercise?")', () {
    final hammer = ex('x-hammer', 'Hammer Curl', year: 2025);
    final hammerDb = ex('x-hammer-db', 'Hammer Dumbbell Curl');
    final inclineDb = ex('x-idb', 'Incline Dumbbell Press');
    final inclineMachine = ex('x-im', 'Incline Machine Chest Press');

    ExerciseLibrary lib(List<CanonicalExercise> list, {List<ExerciseAlias> aliases = const []}) =>
        ExerciseLibrary(exercises: {for (final e in list) e.id: e}, aliases: aliases);

    test('asks about a plausible pair and keeps the more specific name', () {
      final s = suggestExerciseMerges(
        lib([hammer, hammerDb, inclineDb, inclineMachine]),
        inUse: {'x-hammer', 'x-hammer-db', 'x-idb', 'x-im'},
      );
      expect(s, hasLength(1), reason: 'different equipment is never asked');
      expect(s.single.keep.id, 'x-hammer-db');
      expect(s.single.merge.id, 'x-hammer');
    });

    test('never asks about different grips, supports, bars or presses — '
        'the four false pairs found on a real library', () {
      final lib = [
        ex('x-ibp', 'Incline Bench Press'),
        ex('x-idp', 'Incline Dumbbell Press'),
        ex('x-csr', 'Chest-Supported Row'),
        ex('x-bbr', 'Barbell Row'),
        ex('x-hc', 'Hammer Curl'),
        ex('x-dc', 'Dumbbell Curl'),
        ex('x-ez', 'EZ-Bar Curl'),
      ];
      expect(
        suggestExerciseMerges(
          ExerciseLibrary(exercises: {for (final e in lib) e.id: e}),
          inUse: {for (final e in lib) e.id},
        ),
        isEmpty,
      );
    });

    test('never asks about an exercise the user does not use', () {
      expect(
        suggestExerciseMerges(lib([hammer, hammerDb]), inUse: {'x-hammer'}),
        isEmpty,
      );
    });

    test('"Keep separate" is remembered, both ways', () {
      final pair = suggestExerciseMerges(
        lib([hammer, hammerDb]),
        inUse: {'x-hammer', 'x-hammer-db'},
      ).single;
      final marked = markDistinct(pair);
      expect(
        suggestExerciseMerges(lib(marked), inUse: {'x-hammer', 'x-hammer-db'}),
        isEmpty,
      );
    });

    test('a merge is one read-side alias, and removing it undoes it', () {
      final pair = suggestExerciseMerges(
        lib([hammer, hammerDb]),
        inUse: {'x-hammer', 'x-hammer-db'},
      ).single;
      final alias = mergeAlias(pair, now: DateTime(2026, 9));
      expect(alias.source, AliasSource.merge);
      final merged = lib([hammer, hammerDb], aliases: [alias]);
      expect(merged.resolver.canonicalIdOf('x-hammer'), 'x-hammer-db');
      expect(
        suggestExerciseMerges(merged, inUse: {'x-hammer', 'x-hammer-db'}),
        isEmpty,
        reason: 'already one exercise',
      );
      expect(lib([hammer, hammerDb]).resolver.canonicalIdOf('x-hammer'), 'x-hammer');
    });
  });
}

void _planEditTests() {
  group('renaming a plan slot', () {
    test('a typo fix or rewording is the same movement', () {
      expect(isDifferentMovement('Bench Pres', 'Bench Press'), isFalse);
      expect(isDifferentMovement('Seated Row (Wide Grip)', 'Wide-Grip Seated Row'), isFalse);
      expect(isDifferentMovement('Hammer Curl', 'Hammer Dumbbell Curl'), isFalse);
    });

    test('other equipment, another variation, or nothing in common is not', () {
      expect(isDifferentMovement('Incline Dumbbell Press', 'Incline Machine Press'), isTrue);
      expect(isDifferentMovement('Dumbbell Row', 'Single-Arm Dumbbell Row'), isTrue);
      expect(isDifferentMovement('Bench Press', 'Squat'), isTrue);
    });

    PlannedExercise slot(String name, {String? exerciseId}) => PlannedExercise(
      id: 's1',
      exerciseId: exerciseId,
      name: name,
      order: 0,
      defaultRestSeconds: 90,
      sets: const [],
    );

    test('keeps the identity for the same movement', () {
      final r = identityAfterEdit(
        before: slot('Bench Pres', exerciseId: 'x-bench'),
        after: slot('Bench Press', exerciseId: 'x-bench'),
        library: const [],
        newId: () => 'x-new',
        now: DateTime(2026),
      );
      expect(r.exerciseId, 'x-bench');
      expect(r.created, isNull);
    });

    test('a different movement gets its own identity — an existing one on a '
        'confident match, else a new one', () {
      final machine = CanonicalExercise(
        id: 'x-machine',
        name: 'Incline Machine Press',
        createdAt: DateTime(2026),
      );
      final linked = identityAfterEdit(
        before: slot('Incline Dumbbell Press', exerciseId: 'x-idb'),
        after: slot('Incline Machine Press', exerciseId: 'x-idb'),
        library: [machine],
        newId: () => 'x-new',
        now: DateTime(2026),
      );
      expect(linked.exerciseId, 'x-machine');
      final fresh = identityAfterEdit(
        before: slot('Bench Press'),
        after: slot('Front Squat'),
        library: const [],
        newId: () => 'x-new',
        now: DateTime(2026),
      );
      expect(fresh.exerciseId, 'x-new');
      expect(fresh.created!.name, 'Front Squat');
    });
  });
}

// ---- fixtures ---------------------------------------------------------------

/// An in-memory plan repository holding only [split] — it seeds a demo split
/// of its own, which would otherwise be migrated too.
Future<InMemoryWorkoutPlanRepository> _plansWith(WorkoutPlan split) async {
  final plans = InMemoryWorkoutPlanRepository();
  await plans.saveSplit(split);
  for (final s in [...plans.splits]) {
    if (s.id != split.id) await plans.deleteSplit(s.id);
  }
  return plans;
}

/// Two days of the owner's real split: seven movements repeated across them
/// under slightly different spellings, plus two that look alike and aren't.
WorkoutPlan _ownerSplit() => _split('owner', [
  _day('a', [
    _slot('a-pec', 'Pec Deck'),
    _slot('a-preacher', 'Preacher Curl'),
    _slot('a-lat', 'Cable Lateral Raise'),
    _slot('a-push', 'Zigzag Pushdown'),
    _slot('a-row', 'Wide-Grip Seated Row'),
    _slot('a-hammer', 'Hammer Curl'),
    _slot('a-rear', 'Rear Pec Deck'),
    _slot('a-incline-db', 'Incline Dumbbell Press'),
  ]),
  _day('b', [
    _slot('b-pec', 'Pec Deck'),
    _slot('b-preacher', 'Preacher Curls'),
    _slot('b-lat', 'Cable Lateral Raises'),
    _slot('b-push', 'EZ Pushdown'),
    _slot('b-row', 'Seated Row (Wide Grip)'),
    _slot('b-hammer', 'Hammer Curl'),
    _slot('b-rear', 'Reverse Pec Deck'),
    _slot('b-incline-machine', 'Incline Machine Chest Press'),
  ], order: 1),
]);

WorkoutPlan _split(String id, List<WorkoutDay> days) => WorkoutPlan(
  id: id,
  name: 'Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  days: days,
);

WorkoutDay _day(String id, List<PlannedExercise> slots, {int order = 0}) =>
    WorkoutDay(id: id, slot: id, label: id, order: order, exercises: slots);

int _order = 0;

PlannedExercise _slot(String id, String name, {String? exerciseId}) =>
    PlannedExercise(
      id: id,
      exerciseId: exerciseId,
      name: name,
      order: _order++,
      defaultRestSeconds: 90,
      sets: const [
        PlannedSet(
          order: 0,
          repTarget: RepTarget.range(8, 12),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
    );

LiveSession _session(String id, String exerciseId, String name, DateTime at) =>
    LiveSession(
      id: id,
      planId: 'owner',
      dayId: 'a',
      dayLabel: 'A',
      startedAt: at,
      completedAt: at.add(const Duration(hours: 1)),
      status: SessionStatus.completed,
      exercises: [
        SessionExercise(
          id: exerciseId,
          exerciseId: exerciseId,
          name: name,
          restSeconds: 90,
          sets: const [
            LoggedSet(
              id: 'x0',
              target: RepTarget.range(8, 12),
              outcome: SetOutcome.completed,
              actualReps: 10,
              actualWeightKg: 50,
            ),
          ],
        ),
      ],
    );

/// A library whose first read never lands (offline at launch).
class _NeverLoadedLibrary implements ExerciseLibraryRepository {
  final saved = <CanonicalExercise>[];

  @override
  ExerciseLibrary get current => ExerciseLibrary.empty;

  @override
  Stream<ExerciseLibrary> watch() async* {
    yield ExerciseLibrary.empty;
    await Completer<void>().future;
  }

  @override
  Future<void> saveExercise(CanonicalExercise exercise) async =>
      saved.add(exercise);

  @override
  Future<void> saveExercises(List<CanonicalExercise> exercises) async =>
      saved.addAll(exercises);

  @override
  Future<void> saveAliases(List<ExerciseAlias> aliases) async {}

  @override
  Future<void> removeAlias(String legacyId) async {}
}
