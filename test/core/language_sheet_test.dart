import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/l10n/language_sheet.dart';
import 'package:zivo/core/l10n/locale_controller.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/l10n/l10n.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Choosing a language has to change the app, not just a stored preference —
/// so this drives the sheet the way a user does and reads the strings back off
/// a live screen.
void main() {
  testWidgets('picking العربية re-renders the app in Arabic and flips it to '
      'RTL; picking English brings it back', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    final controller = LocaleController();
    addTearDown(controller.dispose);

    late String title;
    late TextDirection direction;

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        diet: diet,
        ai: FakeAiRepository(),
        locale: controller,
        // The same wiring `ZivoApp` uses: the controller drives the app's
        // locale, and everything else follows from that.
        child: ValueListenableBuilder<Locale?>(
          valueListenable: controller.locale,
          builder: (context, locale, _) => MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                title = l(context).dietTitle;
                direction = Directionality.of(context);
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showLanguageSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The test host's locale is en_US, so this starts English.
    expect(title, 'Diet');
    expect(direction, TextDirection.ltr);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-ar')));
    await tester.pumpAndSettle();

    expect(controller.locale.value, const Locale('ar'));
    expect(title, 'التغذية');
    expect(direction, TextDirection.rtl);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();

    expect(title, 'Diet');
    expect(direction, TextDirection.ltr);
  });

  testWidgets('the sheet marks the language currently in use', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    final controller = LocaleController(initial: const Locale('ar'));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        diet: diet,
        ai: FakeAiRepository(),
        locale: controller,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showLanguageSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // One tick, on the chosen row — not on "match my phone", which is a
    // different answer that happens to resolve to the same language.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final ticked = find.descendant(
      of: find.byKey(const Key('language-ar')),
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(ticked, findsOneWidget);
  });
}
