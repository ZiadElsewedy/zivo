import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/sleep/data/health_sleep_source.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/core/l10n/locale_controller.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
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
import 'package:zivo/features/workout/data/in_memory_training_day_mark_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_settings_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

/// Boots the whole app in one language and walks its four tabs, failing on any
/// layout error Flutter reports along the way.
///
/// Arabic is not just a string swap: it flips the text direction, and the
/// Arabic glyphs come from a system fallback face (Manrope and Azeret Mono
/// carry no Arabic), so line boxes and text widths are not the ones every
/// English layout was tuned against. Those two together are what produce the
/// overlapping, mirrored chrome users see in Arabic — and nothing in a
/// suite that only ever renders English can see it. This is the cheap
/// standing guard: it boots the real `ZivoApp`, so it covers whatever the
/// shell and the four tabs actually build today.
const _tabIcons = <IconData>[
  AppIcons.today,
  AppIcons.hub,
  AppIcons.ask,
  AppIcons.you,
];

void main() {
  for (final lang in const ['en', 'ar']) {
    testWidgets('the shell lays out cleanly in $lang', (tester) async {
      // A standard modern phone — the width every layout here is tuned for.
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Collect layout errors instead of letting the first one abort the walk,
      // so one run reports every screen that is broken rather than the first.
      final errors = <String>[];
      final priorOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(
        details.exceptionAsString().split('\n').first,
      );
      addTearDown(() => FlutterError.onError = priorOnError);

      await tester.pumpWidget(
        ZivoApp(
          // Sleep, like every other repository here, is injected rather than
          // left to ZivoApp's default — which is Firestore-backed and resolves
          // the signed-in uid through FirebaseAuth at construction, so booting
          // the real app root without it reaches Firebase in a test that has
          // none.
          sleep: InMemorySleepRepository(),
          sleepSource: const UnsupportedSleepSource(),
          locale: LocaleController(initial: Locale(lang)),
          auth: FakeAuthRepository(
            initial: const Authenticated(
              AuthUser(
                uid: 'test-uid',
                email: 'you@zivo.app',
                displayName: 'Ziad',
              ),
            ),
          ),
          profiles: FakeProfileRepository(),
          expenses: InMemoryExpenseRepository(),
          wallet: InMemoryWalletRepository(),
          expenseCategories: InMemoryCategoryRepository(),
          moments: InMemoryMomentRepository(),
          workouts: InMemoryWorkoutRepository(),
          workoutPlans: InMemoryWorkoutPlanRepository(),
          workoutSessions: InMemoryWorkoutSessionRepository(),
          workoutSettings: InMemoryWorkoutSettingsRepository(),
          trainingDayMarks: InMemoryTrainingDayMarkRepository(),
          bodyWeight: InMemoryBodyWeightRepository(),
          diet: InMemoryDietRepository(),
          ai: FakeAiRepository(),
          media: testMediaService(),
        ),
      );
      // Bounded pumps, not pumpAndSettle: Today carries an always-on repeating
      // animation that never settles (see `widget_test.dart`).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      for (final icon in _tabIcons) {
        final tab = find.byIcon(icon);
        if (tab.evaluate().isEmpty) continue;
        await tester.tap(tab.first, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
      }

      expect(
        errors,
        isEmpty,
        reason: 'layout errors while walking the shell in $lang:\n'
            '${errors.join('\n')}',
      );
    });
  }
}
