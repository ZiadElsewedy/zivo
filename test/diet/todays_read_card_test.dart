import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/coaching/rules.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/diet_state_builder.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/widgets/todays_read_card.dart';

/// Today's read is the coaching engine on the screen. These pin the two
/// claims that makes: the sentences are the engine's own — not a second,
/// UI-side interpretation that could drift from what the coach says — and
/// every one of them opens onto the figures it rests on.

const _day = DietDay(
  label: 'Every day',
  meals: [
    Meal(
      id: 'm1',
      label: 'Lunch',
      order: 0,
      items: [FoodItem(name: 'Rice', quantity: 200, unit: 'g', calories: 700)],
    ),
  ],
);

DietState _state({
  int calories = 2200,
  double? proteinG = 160,
  bool log = true,
}) => buildDietState(
  dayKey: '2026-08-30',
  weekday: 7,
  targets: NutritionTargets(
    goal: DietGoal.fatLoss,
    calories: calories,
    proteinG: proteinG,
    source: TargetSource.manual,
    updatedAt: DateTime(2026, 8, 30),
  ),
  planName: 'Cut',
  day: _day,
  consumedMealIds: const {},
  log: log
      ? [
          FoodLogEntry(
            id: 'e1',
            day: DateTime(2026, 8, 30),
            loggedAt: DateTime(2026, 8, 30, 13),
            foodId: 'usda:1',
            foodName: 'Rice',
            quantity: 300,
            unit: 'g',
            grams: 300,
            kcal: 1500,
            proteinG: 60,
            carbsG: 200,
            fatG: 30,
            source: NutritionSource.usdaFdc,
            sourceRef: '1',
            origin: FoodLogOrigin.logged,
          ),
        ]
      : const [],
);

Widget _wrap(DietState state, {int? hour}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: TodaysReadCard(state: state, localHour: hour),
    ),
  ),
);

void main() {
  testWidgets('shows the engine\'s own sentences, not a second reading of the '
      'same numbers', (tester) async {
    final state = _state();
    await tester.pumpWidget(_wrap(state));

    // Every sentence on the card is one `coachingFindings` produced — the
    // same list the AI coach is handed. If these ever diverge, the screen and
    // the coach are recommending different things from identical data.
    final findings = coachingFindings(state);
    expect(findings, isNotEmpty);
    for (final finding in findings) {
      expect(
        find.text(finding.text),
        findsOneWidget,
        reason: 'missing ${finding.code}',
      );
    }
    // And the register each one is in is named, so a warning can't read as
    // an observation.
    expect(find.text('SUGGESTION'), findsOneWidget);
  });

  testWidgets('Why opens onto the state fields the finding rests on', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_state()));

    // Closed by default: the explanation is available, not imposed.
    expect(find.text('Protein left'), findsNothing);

    await tester.tap(find.byKey(const Key('finding-why-protein_shortfall')));
    await tester.pump();

    // The four fields the rule actually read, each with what it says now.
    expect(
      find.byKey(const Key('evidence-protein_shortfall-remaining.proteinG')),
      findsOneWidget,
    );
    expect(find.text('Protein left'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('Calories left'), findsOneWidget);
    expect(find.text('700 kcal'), findsOneWidget);

    // And it closes again.
    await tester.tap(find.byKey(const Key('finding-why-protein_shortfall')));
    await tester.pump();
    expect(find.text('Protein left'), findsNothing);
  });

  testWidgets('a safety warning is named as one', (tester) async {
    await tester.pumpWidget(_wrap(_state(calories: 900, proteinG: null)));

    expect(
      find.byKey(const Key('finding-target_below_safety_floor')),
      findsOneWidget,
    );
    expect(find.text('WARNING'), findsOneWidget);
    expect(find.textContaining('below the 1200 kcal floor'), findsOneWidget);
  });

  testWidgets('an empty log is never rendered as "you ate nothing"', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_state(log: false), hour: 20));

    expect(find.byKey(const Key('finding-nothing_logged')), findsOneWidget);
    expect(find.textContaining("Nothing's been logged"), findsOneWidget);
    // No progress readout at all: with nothing recorded there is no consumed
    // figure to report, and a "0 of 2200" would be a measurement nobody made.
    expect(find.byKey(const Key('finding-calories_consumed')), findsNothing);
  });
}
