import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/readiness/domain/readiness.dart';
import 'package:zivo/features/readiness/presentation/pages/readiness_page.dart';
import 'package:zivo/features/readiness/presentation/widgets/readiness_glance.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';
import '../support/workout_fixtures.dart';

DateTime _middayToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12);
}

Widget _wrapSection({List<LiveSession> sessions = const []}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'test-uid')),
    ),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(seed: sessions),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    music: InertMusicController(),
    child: MaterialApp(
      home: Scaffold(body: ReadinessSection(now: _middayToday)),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the section hides itself when there is nothing to call', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapSection());
    await _settle(tester);

    // No inputs ⇒ computeReadiness is null ⇒ no header and no verdict.
    expect(find.text('READINESS'), findsNothing);
    expect(find.text('Train hard'), findsNothing);
    expect(find.text('Go light'), findsNothing);
    expect(find.text('Rest'), findsNothing);
  });

  testWidgets('a recovered week reads Train hard on Today', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final threeDaysAgo = _middayToday().subtract(const Duration(days: 3));
    await tester.pumpWidget(
      _wrapSection(
        sessions: [session(id: 's', startedAt: threeDaysAgo)],
      ),
    );
    await _settle(tester);

    expect(find.text('READINESS'), findsOneWidget);
    expect(find.text('Train hard'), findsOneWidget);
  });

  testWidgets('the detail page lists the call and how it works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const readiness = Readiness(
      verdict: ReadinessVerdict.rest,
      factors: [
        ReadinessFactor(
          kind: ReadinessFactorKind.sleep,
          direction: ReadinessDirection.limits,
          sleepDurationMinutes: 360,
          sleepDeltaMinutes: -120,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: ReadinessPage(readiness: readiness)),
    );
    await _settle(tester);

    expect(find.text("Today's readiness"), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('How this is worked out'), findsOneWidget);
    // No onOpenAsk was supplied, so the Ask affordance stays hidden.
    expect(find.text('Ask ZIVO about this'), findsNothing);
  });
}
