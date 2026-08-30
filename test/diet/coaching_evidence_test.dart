import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/coaching/evidence.dart';
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

/// `evidenceFor` is what turns a finding's evidence list from a promise into
/// an answer: `remaining.proteinG` means nothing to a user, "Protein left —
/// 100 g" is checkable. These pin the two properties that make it worth
/// showing at all — it only ever *reads* the state, and it drops what it
/// cannot honestly say.

NutritionTargets _targets({
  int calories = 2200,
  double? proteinG = 160,
  double? carbsG,
  double? fatG,
  DietGoal goal = DietGoal.fatLoss,
}) => NutritionTargets(
  goal: goal,
  calories: calories,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  source: TargetSource.manual,
  updatedAt: DateTime(2026, 8, 30),
);

FoodLogEntry _logged({
  int kcal = 1500,
  double proteinG = 60,
  bool estimated = false,
  FoodLogOrigin origin = FoodLogOrigin.logged,
}) => FoodLogEntry(
  id: 'e1',
  day: DateTime(2026, 8, 30),
  loggedAt: DateTime(2026, 8, 30, 13),
  foodId: 'usda:1',
  foodName: 'Rice',
  quantity: 300,
  unit: 'g',
  grams: 300,
  kcal: kcal,
  proteinG: proteinG,
  carbsG: 200,
  fatG: 30,
  source: NutritionSource.usdaFdc,
  sourceRef: '1',
  origin: origin,
  estimated: estimated,
);

const _day = DietDay(
  label: 'Every day',
  meals: [
    Meal(
      id: 'm1',
      label: 'Lunch',
      order: 0,
      items: [
        FoodItem(
          name: 'Rice',
          quantity: 200,
          unit: 'g',
          calories: 700,
          proteinG: 14,
          carbsG: 150,
          fatG: 2,
          estimated: true,
        ),
      ],
    ),
  ],
);

DietState _state({
  NutritionTargets? targets,
  List<FoodLogEntry> log = const [],
  Set<String> ticked = const {},
  DietDay? day = _day,
}) => buildDietState(
  dayKey: '2026-08-30',
  weekday: 7,
  targets: targets,
  planName: 'Cut',
  day: day,
  consumedMealIds: ticked,
  log: log,
);

Map<String, String> _byLabel(List<EvidenceValue> values) => {
  for (final v in values) v.label: v.value,
};

void main() {
  test(
    'resolves a real finding\'s evidence into figures the user can check',
    () {
      final state = _state(targets: _targets(), log: [_logged()]);
      final finding = coachingFindings(
        state,
      ).firstWhere((f) => f.code == 'protein_shortfall');

      final resolved = _byLabel(evidenceFor(state, finding.evidence));

      // Exactly the four fields the rule read, and what each one says now.
      expect(resolved, {
        'Protein left': '100 g',
        'Protein target': '160 g',
        'Calories left': '700 kcal',
        'Daily target': '2200 kcal',
      });
      // Order follows the finding's own evidence list — the rule's reading
      // order, not this map's.
      expect(
        evidenceFor(state, finding.evidence).map((v) => v.path).toList(),
        finding.evidence,
      );
    },
  );

  test('a path it does not know is dropped, not rendered blank', () {
    final state = _state(targets: _targets(), log: [_logged()]);
    final resolved = evidenceFor(state, const [
      'consumed.kcal',
      'targets.somethingNobodyImplemented',
    ]);
    expect(resolved.map((v) => v.label), ['Eaten today']);
  });

  test('two paths naming the same fact collapse into one row', () {
    final state = _state(targets: _targets(), ticked: {'m1'});
    final resolved = evidenceFor(state, const [
      'consumed.basis',
      'quality.consumedIsAssumed',
    ]);
    expect(resolved, hasLength(1));
    expect(resolved.single.value, 'from the meals you ticked, not weighed');
  });

  test('an unset target reads as "not set" — never as a zero', () {
    final state = _state(targets: _targets(proteinG: null));
    final resolved = _byLabel(
      evidenceFor(state, const ['targets.proteinG', 'quality.untrackedMacros']),
    );
    expect(resolved['Protein target'], 'not set');
    expect(resolved['Untracked macros'], 'protein, carbs, fat');

    // And with no targets at all, the daily figure says so rather than
    // reporting a target of 0.
    final none = _state();
    expect(
      _byLabel(evidenceFor(none, const ['targets.calories']))['Daily target'],
      'not set',
    );
    // A "left" figure that doesn't exist produces no row at all.
    expect(evidenceFor(none, const ['remaining.kcal']), isEmpty);
  });

  test('a total resting on estimated values carries the same "~" the rest of '
      'the app uses', () {
    // Nothing logged, one ticked plan meal whose items were AI-estimated at
    // import time: the consumed figure is an estimate of an assumption.
    final state = _state(targets: _targets(), ticked: {'m1'});
    final resolved = _byLabel(
      evidenceFor(state, const ['consumed.kcal', 'quality.hasEstimatedValues']),
    );
    expect(resolved['Eaten today'], '~700 kcal');
    expect(resolved['Estimated figures'], contains('imported plan'));
  });

  test('past the target it reads as "over by", not as a negative number', () {
    final state = _state(
      targets: _targets(calories: 1200, proteinG: 100),
      log: [_logged(kcal: 1500, proteinG: 130)],
    );
    final resolved = _byLabel(
      evidenceFor(state, const ['remaining.kcal', 'remaining.proteinG']),
    );
    expect(resolved['Over target by'], '300 kcal');
    expect(resolved['Protein over by'], '30 g');
  });

  test('every finding the engine emits can explain itself', () {
    // The guard that keeps the "Why" honest: a rule whose evidence resolves
    // to nothing would render an unopenable claim, which is exactly the
    // asserted-not-answerable coaching this whole stack exists to end.
    final states = <DietState>[
      _state(targets: _targets(), log: [_logged()]),
      _state(targets: _targets(), ticked: {'m1'}),
      _state(targets: _targets(calories: 900)),
      _state(targets: _targets(calories: 1200), log: [_logged(kcal: 1800)]),
      _state(),
      _state(targets: _targets(), day: null),
    ];
    for (final state in states) {
      for (final hour in <int?>[null, 9, 20]) {
        for (final finding in coachingFindings(state, localHour: hour)) {
          expect(
            evidenceFor(state, finding.evidence),
            isNotEmpty,
            reason: '${finding.code} has no resolvable evidence',
          );
        }
      }
    }
  });
}
