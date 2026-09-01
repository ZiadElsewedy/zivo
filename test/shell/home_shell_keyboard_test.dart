import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/widgets/voice_composer.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

/// The composer must sit ON the keyboard, not a nav-island's height above it.
///
/// This has to boot the whole shell: the bug only existed in the seam between
/// the two scaffolds. `HomeShell`'s scaffold used to resize for the keyboard,
/// which both shrank the tab body to the keyboard's top edge AND stripped
/// `viewInsets` from the body's `MediaQuery` — so Ask, which lifts its own
/// composer, read a zero inset and fell back to reserving the bottom chrome.
/// Hosting `AskPage` on its own (as every other Ask test does) can't see it.
void main() {
  testWidgets('Ask composer rests on the keyboard inside the shell', (
    tester,
  ) async {
    const height = 2000.0;
    const keyboard = 700.0;
    tester.view.physicalSize = const Size(1000, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ZivoApp(
        auth: FakeAuthRepository(
          initial: const Authenticated(AuthUser(uid: 'test-uid')),
        ),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        wallet: InMemoryWalletRepository(),
        expenseCategories: InMemoryCategoryRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        bodyWeight: InMemoryBodyWeightRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        media: testMediaService(),
      ),
    );
    // Bounded pumps, not pumpAndSettle: Today carries an always-on repeating
    // animation that never settles (see `widget_test.dart`).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    await tester.tap(find.text('ASK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    // Raise the keyboard.
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pump();
    // Past the composer's own eased lift (260ms).
    await tester.pump(const Duration(milliseconds: 400));

    final composer = tester.getRect(find.byType(VoiceComposer));
    expect(
      composer.bottom,
      moreOrLessEquals(height - keyboard, epsilon: 0.5),
      reason: 'the composer should end exactly at the keyboard top edge',
    );
  });
}
