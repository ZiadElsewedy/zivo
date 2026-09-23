import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/diet/presentation/pages/diet_import_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  testWidgets('"Claude isn\'t available" on the plan screen can be fixed '
      'there: Switch model → Gemini Flash → the build retries', (tester) async {
    final working = FakeAiRepository();
    addTearDown(working.dispose);
    var calls = 0;
    late final FakeAiRepository ai;
    ai = FakeAiRepository(
      generateDietPlanImpl: (preferences, targets) async {
        calls++;
        // Whatever is saved as active when the call is made: Claude fails,
        // Gemini answers — the way the server routes by the saved choice.
        if (await ai.getModelSelection() != 'gemini-flash') {
          throw const AiFailure(
            AiFailureKind.unavailable,
            provider: 'anthropic',
            issue: AiProviderIssue.notConfigured,
          );
        }
        return working.generateDietPlan(preferences: preferences);
      },
    );
    addTearDown(ai.dispose);

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
        ai: ai,
        child: const MaterialApp(
          home: DietImportPage(generateFrom: PlanPreferences(mealsPerDay: 3)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Claude isn't available"), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-error-secondary')));
    await tester.pumpAndSettle();

    // The sheet shows Claude Sonnet active; pick Gemini Flash.
    await tester.tap(find.byKey(const Key('sheet-model-gemini-flash')));
    await tester.pumpAndSettle();

    expect(await ai.getModelSelection(), 'gemini-flash');
    expect(calls, 2, reason: 'picking a model retries the build');
    expect(find.textContaining("Claude isn't available"), findsNothing);
  });
}
