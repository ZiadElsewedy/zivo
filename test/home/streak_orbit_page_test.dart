import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/presentation/pages/streak_orbit_page.dart';
import 'package:zivo/features/home/presentation/widgets/today_pulse_card.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';

import '../support/test_app.dart';
import '../support/workout_fixtures.dart';

/// The Streak Orbit — the visual consistency scene opened from Today's
/// Momentum card. The mechanics live in `computeTrainingStreak` (tested in
/// `training_streak_test.dart`); these tests pin the scene's own readings and
/// the tap that reaches it.
///
/// The page runs a looping ambient animation, so every pump here is an
/// explicit `pump()` — never `pumpAndSettle`, which would spin forever on the
/// orbit's rotation.

DateTime _daysAgo(int n) =>
    DateTime.now().subtract(Duration(days: n)).copyWith(hour: 12, minute: 0);

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpOrbit(
  WidgetTester tester, {
  required List<LiveSession> sessions,
}) async {
  await tester.pumpWidget(
    wrapWithScope(
      const StreakOrbitPage(),
      workoutSessions: InMemoryWorkoutSessionRepository(seed: sessions),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a live run shows the streak count, the rule and the records', (
    tester,
  ) async {
    _bigScreen(tester);

    // Trained today and two days ago — inside the 3-day allowance, so the run
    // is two days long.
    await _pumpOrbit(
      tester,
      sessions: [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(2)),
      ],
    );

    // The flame's caption and the two record tiles, all present.
    expect(find.text('DAY STREAK'), findsOneWidget);
    expect(find.text('BEST STREAK'), findsOneWidget);
    expect(find.text('DAYS TRAINED'), findsOneWidget);
    // The rule that gives the number meaning, mirrored from the hub page.
    expect(find.text('Train at least every 3 days'), findsOneWidget);
    // The current run is two days — the hero figure and both records read 2.
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('a broken streak reads zero and invites a fresh start', (
    tester,
  ) async {
    _bigScreen(tester);

    // Trained six days ago and not since: the allowance has run out, so there
    // is no active run.
    await _pumpOrbit(tester, sessions: [session(id: 'a', startedAt: _daysAgo(6))]);

    expect(find.text('0'), findsOneWidget);
    expect(find.text('No active streak'), findsOneWidget);
    expect(find.text('Train today and day one starts now.'), findsOneWidget);
  });

  testWidgets('tapping the Momentum card opens the Streak Orbit', (
    tester,
  ) async {
    _bigScreen(tester);

    await tester.pumpWidget(
      wrapWithScope(
        const Scaffold(body: MomentumSection()),
        workoutSessions: InMemoryWorkoutSessionRepository(
          seed: [session(id: 'a', startedAt: _daysAgo(0))],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StreakOrbitPage), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    // Let the push route settle a frame or two — not to completion, since the
    // destination animates forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StreakOrbitPage), findsOneWidget);
  });
}
