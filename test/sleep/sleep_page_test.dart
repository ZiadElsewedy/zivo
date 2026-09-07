import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_service.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_source.dart';
import 'package:zivo/features/sleep/presentation/pages/sleep_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/bidi_finders.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Cover for the Sleep screen's **claims** — the sentences it is and is not
/// entitled to put in front of a user.
///
/// The engine's correctness is covered in `sleep_domain_test.dart`. What this
/// file guards is the last few inches, where a correct record can still be
/// rendered as a false statement: a typed entry described as a detection, an
/// unreadable store described as an empty one, a missing night drawn as zero
/// hours slept. Every one of those would leave the data layer perfectly
/// correct and the screen lying.

class _FakeSource implements SleepSource {
  _FakeSource({
    this.records = const [],
    this.authorization = SleepAuthorization.granted,
    this.available = true,
  });

  final List<RawSleepRecord> records;
  final SleepAuthorization authorization;
  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SleepAuthorization> authorizationStatus() async => authorization;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  }) async => records;
}

/// Last night, 23:47 → 06:59 local, as the platform would hand it over.
///
/// Built relative to today rather than pinned to a fixed date: the page syncs
/// on open and a night outside the sync window would be withdrawn — correctly,
/// since sync's job is to reconcile with the store — leaving the test asserting
/// against an empty screen for the wrong reason.
///
/// The metadata is chosen so `methodFor` *derives* the method under test
/// rather than the test asserting one, which is the behaviour that actually
/// matters: an entry's tier has to fall out of what the platform said.
RawSleepRecord _record(SleepMethod method) {
  final now = DateTime.now();
  final localStart = DateTime(now.year, now.month, now.day - 1, 23, 47);
  final localEnd = DateTime(now.year, now.month, now.day, 6, 59);

  return RawSleepRecord(
    id: 'r1',
    startAt: localStart.toUtc(),
    endAt: localEnd.toUtc(),
    startOffsetMinutes: localStart.timeZoneOffset.inMinutes,
    endOffsetMinutes: localEnd.timeZoneOffset.inMinutes,
    stage: SleepStage.asleepUnspecified,
    providerId: switch (method) {
      SleepMethod.measuredWearable => 'com.apple.health',
      SleepMethod.userReported => 'com.apple.health',
      _ => 'com.example.tracker',
    },
    providerName: switch (method) {
      SleepMethod.measuredWearable => 'Apple Health',
      SleepMethod.userReported => 'You',
      _ => 'SomeSleepApp',
    },
    deviceKind: method == SleepMethod.measuredWearable
        ? SleepDeviceKind.watch
        : SleepDeviceKind.unknown,
    recordingMethod: method == SleepMethod.userReported
        ? SleepRecordingMethod.manual
        : SleepRecordingMethod.automatic,
  );
}

/// An estimated night, seeded directly.
///
/// `methodFor` cannot produce [SleepMethod.deviceEstimated] from platform
/// metadata — nothing writes estimates into HealthKit or Health Connect, and
/// the Android Sleep API path is not wired (docs/SLEEP_SYSTEM.md §20). So this
/// one is seeded, and its source reports unavailable so the sync that follows
/// does not reconcile it away.
SleepNight _estimatedNight() {
  final now = DateTime.now();
  final localStart = DateTime(now.year, now.month, now.day - 1, 23, 47);
  final localEnd = DateTime(now.year, now.month, now.day, 6, 59);

  return SleepNight(
    sleepDay: DateTime(now.year, now.month, now.day),
    main: SleepSession(
      id: 'estimate',
      startAt: localStart.toUtc(),
      endAt: localEnd.toUtc(),
      startOffsetMinutes: localStart.timeZoneOffset.inMinutes,
      endOffsetMinutes: localEnd.timeZoneOffset.inMinutes,
      provenance: SleepProvenance(
        method: SleepMethod.deviceEstimated,
        providerId: 'android.sleep',
        providerName: 'Android Sleep API',
        deviceKind: SleepDeviceKind.phone,
        recordingMethod: SleepRecordingMethod.automatic,
        confidence: SleepConfidence.low,
        completeness: 0.6,
        rawRefs: const [],
        ingestedAt: now,
      ),
    ),
    resolution: SleepResolution.soleSource,
  );
}

Future<InMemorySleepRepository> _pump(
  WidgetTester tester, {
  SleepMethod? method,
  SleepNight? seeded,
  SleepAuthorization authorization = SleepAuthorization.granted,
  bool available = true,
}) async {
  final repository = InMemorySleepRepository();
  if (seeded != null) await repository.upsertNights([seeded]);

  final service = SleepService(
    repository: repository,
    source: _FakeSource(
      records: method == null ? const [] : [_record(method)],
      authorization: authorization,
      available: available,
    ),
  );

  await tester.pumpWidget(
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      sleep: repository,
      sleepService: service,
      child: const MaterialApp(home: SleepPage()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  // The page is one long scroll and a ListView only builds what is visible, so
  // the default 800x600 surface would leave the week and the insights
  // unbuilt — and "not rendered" would read exactly like "not found".
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1400, 4000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a measured night says "Asleep" and names its source', (
    tester,
  ) async {
    await _pump(tester, method: SleepMethod.measuredWearable);

    // The hero is set as rich text — number in mono, unit in the text face —
    // so the composed duration lives on its semantics label, which is also
    // exactly what a screen reader is handed.
    expect(find.bySemanticsLabel('7h 12m'), findsOneWidget);
    expect(findTextIgnoringBidi('Asleep 11:47 PM'), findsOneWidget);
    // The source chip is not optional chrome — a duration without it is the
    // claim this feature exists to refuse.
    expect(findTextIgnoringBidi('Apple Health · Measured'), findsOneWidget);
  });

  testWidgets('a user-reported night says "You logged", never "Asleep"', (
    tester,
  ) async {
    await _pump(tester, method: SleepMethod.userReported);

    expect(findTextIgnoringBidi('You logged 11:47 PM'), findsOneWidget);
    expect(findTextIgnoringBidi('Asleep 11:47 PM'), findsNothing);
    expect(findTextIgnoringBidi('You · Logged by you'), findsOneWidget);
  });

  testWidgets('an unattributed platform record says "recorded", not "asleep"',
      (tester) async {
    await _pump(tester, method: SleepMethod.platformDerived);

    expect(findTextIgnoringBidi('Sleep recorded 11:47 PM'), findsOneWidget);
    expect(findTextIgnoringBidi('Asleep 11:47 PM'), findsNothing);
  });

  testWidgets('an estimate is hedged AND rounded to the quarter hour', (
    tester,
  ) async {
    // Both halves matter: "around 11:47" would be a hedge wrapped around a
    // precision the hedge contradicts.
    await _pump(tester, seeded: _estimatedNight(), available: false);

    expect(
      findTextIgnoringBidi('Likely asleep around 11:45 PM'),
      findsOneWidget,
    );
    expect(findTextIgnoringBidi('Likely asleep around 11:47 PM'), findsNothing);
  });

  testWidgets('with nothing recorded the screen never shows a zero', (
    tester,
  ) async {
    await _pump(tester);

    expect(findTextIgnoringBidi('0h 0m'), findsNothing);
    expect(findTextIgnoringBidi('0m'), findsNothing);
    expect(find.bySemanticsLabel('0h 0m'), findsNothing);
    expect(find.bySemanticsLabel('0m'), findsNothing);
  });

  testWidgets(
      'an empty read we were not confirmed to be allowed does not claim '
      'there is no data', (tester) async {
    // The iOS case. Apple never reports read denial, so an empty result may
    // mean "refused" — asserting emptiness would be a claim with nothing
    // behind it.
    await _pump(tester, authorization: SleepAuthorization.unknown);

    expect(
      findTextIgnoringBidi('No sleep data visible to ZIVO'),
      findsOneWidget,
    );
    expect(findTextIgnoringBidi('No sleep recorded'), findsNothing);
  });

  testWidgets('a confirmed-empty store may say there is no sleep recorded', (
    tester,
  ) async {
    await _pump(tester, authorization: SleepAuthorization.granted);

    expect(findTextIgnoringBidi('No sleep recorded'), findsOneWidget);
    expect(findTextIgnoringBidi('No sleep data visible to ZIVO'), findsNothing);
  });

  testWidgets('a host with no health store still offers manual logging', (
    tester,
  ) async {
    await _pump(tester, available: false);

    expect(findTextIgnoringBidi('No health app on this device'), findsOneWidget);
    expect(findTextIgnoringBidi("I'm going to sleep"), findsOneWidget);
  });

  testWidgets('gated figures state how far off they are, and show no number',
      (tester) async {
    await _pump(tester, method: SleepMethod.measuredWearable);

    // One night is below every window gate: the week's figures must say so
    // rather than averaging a single night into a "weekly average".
    expect(findTextIgnoringBidi('Not enough nights yet — 1 of 3'), findsWidgets);
    expect(
      findTextIgnoringBidi('No conclusion can be drawn from the nights '
          'recorded so far.'),
      findsOneWidget,
    );
  });

  testWidgets('logging a sleep mark opens it, and waking closes it as '
      'user-reported', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(findTextIgnoringBidi("I'm going to sleep"));
    await tester.pumpAndSettle();

    expect(repository.currentOpenMark, isNotNull);
    expect(findTextIgnoringBidi("I'm awake"), findsOneWidget);
  });
}
