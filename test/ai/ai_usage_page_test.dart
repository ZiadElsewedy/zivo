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
  testWidgets('shows the total, per-provider and per-feature spend, and each '
      'request with its fallback/failure badge', (tester) async {
    await tester.pumpWidget(
      AppScope(
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-usage-total-cost')), findsOneWidget);
    // Both providers and the features the fake logged.
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Diet plan builder'), findsWidgets);
    expect(find.text('Voice to text'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Failed'), 300);
    expect(find.text('Backup model'), findsWidgets);
    expect(find.text('Failed'), findsOneWidget);
  });
}
