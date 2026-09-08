import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_typography.dart';
import 'package:zivo/core/theme/theme_controller.dart';
import 'package:zivo/core/theme/theme_sheet.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
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

/// Choosing a skin has to change the app, not just a stored preference — so
/// this drives the sheet the way a user does and reads the colours back off a
/// live screen, the same way the language test reads strings back.
void main() {
  // The active palette is process-wide (ADR-011), so a test that changes it
  // puts it back.
  tearDown(() => ZivoTheme.use(Brightness.dark));

  Widget host(ThemeController controller, {VoidCallback? onBuild}) {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    return AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: diet,
      ai: FakeAiRepository(),
      theme: controller,
      // The same wiring `ZivoApp` uses: the controller swaps the active
      // palette above every route, and the screens follow from that.
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: controller.mode,
        builder: (context, mode, _) {
          ZivoTheme.use(
            mode == ThemeMode.light ? Brightness.light : Brightness.dark,
          );
          return MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                onBuild?.call();
                return Scaffold(
                  backgroundColor: TrainColors.base,
                  body: Center(
                    child: TextButton(
                      onPressed: () => showThemeSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  testWidgets('picking Light re-skins the live screen, and Dark brings the '
      'near-black back', (tester) async {
    final controller = ThemeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    Color ground() => tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;

    expect(ground(), ZivoPalette.dark.base);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();

    expect(controller.mode.value, ThemeMode.light);
    expect(ground(), ZivoPalette.light.base);
    // Not just the ground: the ink that sits on it has to have turned over
    // too, or the screen is white-on-white.
    expect(TrainColors.ink, ZivoPalette.light.ink);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();

    expect(ground(), ZivoPalette.dark.base);
    expect(TrainColors.ink, ZivoPalette.dark.ink);
  });

  testWidgets('the sheet marks the skin currently chosen', (tester) async {
    final controller = ThemeController(initial: ThemeMode.system);
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // One tick, on "match my phone" — not on Dark, which is what that choice
    // currently resolves to but is a different answer.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('theme-system')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the type ladder answers to the skin too', (tester) async {
    // `AppText`'s steps were `static` *fields*, which Dart evaluates once, on
    // first touch — the whole app would have kept the ink of whichever skin
    // happened to draw first. This is the regression guard for that.
    final controller = ThemeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    expect(AppText.rowTitle.color, ZivoPalette.dark.ink);
    expect(AppText.body.color, ZivoPalette.dark.ink2);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();

    expect(AppText.rowTitle.color, ZivoPalette.light.ink);
    expect(AppText.body.color, ZivoPalette.light.ink2);
  });
}
