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
  setUp(ZivoTheme.resetForTesting);
  tearDown(ZivoTheme.resetForTesting);

  Widget host(
    ThemeController controller, {
    VoidCallback? onBuild,
    Widget? home,
  }) {
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
            home:
                home ??
                Builder(
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

    Color ground() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;

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

  testWidgets('a const screen repaints when the skin flips', (tester) async {
    // The bug this is here for: `TrainColors` is read by name, so nothing in
    // the tree is subscribed to it, and `Element.updateChild` skips any child
    // whose widget compares equal to the one it already has. Every `const`
    // widget does — `home: const AuthGate()` kept the whole app on whichever
    // skin it was first built in, and only screens that a stream tick
    // happened to rebuild came out right.
    final controller = ThemeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, home: const _ConstScreen()));
    await tester.pumpAndSettle();
    expect(_ConstScreen.lastPainted, ZivoPalette.dark.ink);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();

    expect(
      _ConstScreen.lastPainted,
      ZivoPalette.light.ink,
      reason: 'the const screen kept the skin it was first built in',
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

/// A `const` screen with the picker on it — the shape `ZivoApp` uses for
/// `home:`, and the one that exposed the missing repaint.
class _ConstScreen extends StatelessWidget {
  const _ConstScreen();

  /// The ink this screen last actually painted with.
  static Color? lastPainted;

  @override
  Widget build(BuildContext context) {
    lastPainted = TrainColors.ink;
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: Center(
        child: TextButton(
          onPressed: () => showThemeSheet(context),
          child: const Text('open'),
        ),
      ),
    );
  }
}
