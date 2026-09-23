import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/pages/ai_usage_page.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  testWidgets('switching provider shows that provider\'s own requests, '
      'tokens and cost', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Claude first: the fake logged a chat turn and a workout import.
    expect(find.byKey(const Key('ai-usage-total-cost')), findsOneWidget);
    expect(find.byKey(const Key('ai-usage-cost-per-request')), findsOneWidget);
    expect(_stat(tester, 'stat-requests-0'), '2'); // total
    expect(_stat(tester, 'stat-requests-1'), '1'); // chat
    expect(_stat(tester, 'stat-requests-3'), '1'); // import
    expect(find.text('Input tokens'), findsOneWidget);
    expect(find.text('Output tokens'), findsOneWidget);

    // Gemini: plan builder + voice + a failed chat.
    await tester.tap(find.byKey(const Key('usage-provider-gemini')));
    await tester.pumpAndSettle();
    expect(_stat(tester, 'stat-requests-0'), '3');
    expect(_stat(tester, 'stat-requests-2'), '1'); // generate
    expect(find.text('Failed requests'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Failed'), 300);
    expect(find.text('Failed'), findsOneWidget);
  });
}

/// The figure on a stat row.
String? _stat(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
  );
  return texts.last.data;
}

Widget _host() => AppScope(
  auth: FakeAuthRepository(
    initial: const Authenticated(AuthUser(uid: 'fake-uid')),
  ),
  profiles: FakeProfileRepository(),
  bodyWeight: InMemoryBodyWeightRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: FakeAiRepository(),
  child: const MaterialApp(home: AiUsagePage()),
);
