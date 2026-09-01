import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/device/steps/step_counter.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/home/presentation/pages/today_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';

/// A step counter that just replays [steps] — the dashboard's device-data
/// input, without touching CoreMotion.
class _FakeStepCounter implements StepCounterService {
  _FakeStepCounter(this.steps);

  final int steps;

  @override
  Stream<int> watchStepsToday() => Stream.value(steps);
}

const WorkoutDay _day = WorkoutDay(
  id: 'd',
  slot: 'A',
  label: 'Pull',
  order: 0,
  exercises: [],
);

LiveSession _done(DateTime at, String id) => LiveSession.start(
  _day,
  id: id,
  planId: 'p',
  now: at,
).complete(now: at.add(const Duration(minutes: 40)));

/// Today at [hour] — a fixed instant for the insights strip.
///
/// Two of the nudge rules are hour-of-day rules (steps from 16:00, diet from
/// 19:00), so a test that lets the strip read the real clock asserts a
/// different screen depending on when it runs. Today's *date* is kept so
/// sessions and weigh-ins seeded relative to `DateTime.now()` still land in
/// the windows the other rules measure.
DateTime _todayAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour);
}

Widget _wrap({
  StepCounterService? stepCounter,
  InMemoryBodyWeightRepository? bodyWeight,
  WorkoutSessionRepository? workoutSessions,
  DietRepository? diet,
  DateTime Function()? now,
}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'test-uid')),
    ),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: workoutSessions ?? InMemoryWorkoutSessionRepository(),
    bodyWeight: bodyWeight,
    diet: diet ?? InMemoryDietRepository(),
    ai: FakeAiRepository(),
    music: InertMusicController(),
    stepCounter: stepCounter,
    child: MaterialApp(home: TodayPage(now: now)),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1100));
  await tester.pump();
}

void main() {
  testWidgets('the pulse card answers all three rings with real data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _done(now.subtract(const Duration(days: 1)), 'y'),
        _done(now, 't'),
      ],
    );

    await tester.pumpWidget(
      _wrap(stepCounter: _FakeStepCounter(6500), workoutSessions: sessions),
    );
    await _settle(tester);

    // Train: a session completed today → filled + "Trained".
    expect(find.text('Trained'), findsOneWidget);
    // Move: fake device steps render compacted with the goal caption. The
    // ring splits the number from its unit into separate slots now (so the
    // digits keep the hero size and the "k" reads as a unit), and the caption
    // is the mono "OF 8K".
    expect(find.text('6.5'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(find.text('OF 8K'), findsOneWidget);
    // Volume: the third ring is training tonnage now. The pulse card's rings
    // are Trained · Steps · Volume — all three about training. The diet ring
    // that used to sit here moved out to its own glance row (asserted below),
    // so the card answers one question instead of two.
    expect(find.text('Volume'), findsOneWidget);
    // Fuel still shows on Today, as the diet glance line: the default
    // in-memory diet repo seeds a 3-meal plan with none eaten yet.
    expect(find.textContaining('0 of 3 meals eaten'), findsOneWidget);
  });

  testWidgets('momentum appears once history exists and shows the streak', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        for (var i = 0; i < 3; i++)
          _done(now.subtract(Duration(days: i)), 's$i'),
      ],
    );

    await tester.pumpWidget(_wrap(workoutSessions: sessions));
    await _settle(tester);

    expect(find.text('MOMENTUM'), findsOneWidget);
    expect(find.text('3-day streak'), findsOneWidget);
    expect(find.text('3 SESSIONS · LAST 7 DAYS'), findsOneWidget);
  });

  testWidgets(
    'the momentum row survives a narrow screen with no streak — two captions '
    'on one line must ellipsise, never overflow (regression)',
    (tester) async {
      // A real phone width, not the roomy 1200 the other tests use: the row
      // carries a left caption AND a right caption, and when the left one was
      // added it pushed the pair past the edge on an actual device.
      tester.view.physicalSize = const Size(375, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Two sessions, but not on consecutive days → no streak, so the left
      // slot shows its low-data caption beside the busiest right-hand one.
      final now = DateTime.now();
      final sessions = InMemoryWorkoutSessionRepository(
        seed: [
          _done(now, 'a'),
          _done(now.subtract(const Duration(days: 3)), 'b'),
        ],
      );

      await tester.pumpWidget(_wrap(workoutSessions: sessions));
      await _settle(tester);

      expect(find.text('NO STREAK YET'), findsOneWidget);
      expect(find.text('2 SESSIONS · LAST 7 DAYS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a brand-new user sees neither momentum nor insights — '
      'nothing bluffs', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A genuinely empty account, judged at 20:00 — the hour at which every
    // nudge rule that has one is open for business. Nothing may still speak.
    // The diet repo is the `.empty()` one on purpose: the default seeds a
    // demo plan, and "3 meals left today" is a true statement about that
    // fixture rather than about the user, so the evening nudge used to fire
    // here on a user who had entered nothing. This test failed after 19:00
    // and passed before it.
    await tester.pumpWidget(
      _wrap(diet: InMemoryDietRepository.empty(), now: () => _todayAt(20)),
    );
    await _settle(tester);

    expect(find.text('MOMENTUM'), findsNothing);
    expect(find.text('WORTH KNOWING'), findsNothing);
  });

  testWidgets('device steps feed the insights strip (shortfall nudge)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The nudge only speaks from 16:00, so the clock is pinned rather than
    // read: this assertion used to be wrapped in `if (DateTime.now().hour >=
    // 16)`, which meant that for most of the day the test proved the nudge
    // was ABSENT and never once checked the thing it is named after.
    await tester.pumpWidget(
      _wrap(stepCounter: _FakeStepCounter(6500), now: () => _todayAt(18)),
    );
    await _settle(tester);

    expect(find.textContaining('Steps are behind today'), findsOneWidget);
  });

  testWidgets('...and stays quiet before 16:00, with the same 6.5k steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(stepCounter: _FakeStepCounter(6500), now: () => _todayAt(9)),
    );
    await _settle(tester);

    expect(find.textContaining('Steps are behind today'), findsNothing);
  });

  testWidgets('weight trend renders from logged weigh-ins', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final bodyWeight = InMemoryBodyWeightRepository();
    await bodyWeight.save(
      BodyWeightEntry(
        id: 'w1',
        weightKg: 82.4,
        loggedAt: now.subtract(const Duration(days: 12)),
      ),
    );
    await bodyWeight.save(
      BodyWeightEntry(id: 'w2', weightKg: 81.6, loggedAt: now),
    );

    await tester.pumpWidget(_wrap(bodyWeight: bodyWeight));
    await _settle(tester);

    // The figure and its unit are separate elements now — the unit stays
    // smaller and dimmer than the value, and the delta states its baseline.
    expect(find.text('−0.8'), findsOneWidget);
    expect(find.text('KG · 14D'), findsOneWidget);
  });
}
