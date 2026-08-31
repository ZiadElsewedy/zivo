import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/coaching/finding.dart';
import 'package:zivo/features/diet/domain/coaching/rules.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/body_measures.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/diet_state_builder.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';

/// The Dart half of the shared coaching vectors, plus the rules' own
/// behaviour.
///
/// `test/fixtures/coaching_vectors.json` is run by BOTH this file and
/// `functions/diet/rules.test.js`. The engine decides what the coach says;
/// two implementations of that decision disagreeing means the app and the
/// coach recommend different things from identical data.
///
/// Half of these assert the NEGATIVES. A rules engine is defined as much by
/// what it stays quiet about — generic nagging is the failure mode it exists
/// to replace.

DietDay _dayFrom(Map<String, dynamic> raw) => DietDay(
  label: raw['label'] as String,
  meals: [
    for (final m in (raw['meals'] as List).cast<Map<String, dynamic>>())
      Meal(
        id: m['id'] as String,
        label: m['label'] as String,
        order: 0,
        items: [
          for (final i in (m['items'] as List).cast<Map<String, dynamic>>())
            FoodItem(
              name: i['name'] as String,
              quantity: (i['quantity'] as num).toDouble(),
              unit: i['unit'] as String,
              calories: (i['calories'] as num?)?.toInt(),
              proteinG: (i['proteinG'] as num?)?.toDouble(),
              carbsG: (i['carbsG'] as num?)?.toDouble(),
              fatG: (i['fatG'] as num?)?.toDouble(),
              estimated: i['estimated'] == true,
            ),
        ],
      ),
  ],
);

NutritionTargets? _targetsFrom(Map<String, dynamic>? raw) => raw == null
    ? null
    : NutritionTargets(
        goal: dietGoalFromName(raw['goal'] as String?)!,
        calories: (raw['calories'] as num).toInt(),
        proteinG: (raw['proteinG'] as num?)?.toDouble(),
        carbsG: (raw['carbsG'] as num?)?.toDouble(),
        fatG: (raw['fatG'] as num?)?.toDouble(),
        source: targetSourceFromName(raw['source'] as String?),
        updatedAt: DateTime(2026, 8, 30),
      );

FoodLogEntry _entryFrom(Map<String, dynamic> e) => FoodLogEntry(
  id: e['id'] as String,
  day: DateTime(2026, 8, 30),
  loggedAt: DateTime(2026, 8, 30, 12),
  foodId: e['foodId'] as String,
  foodName: e['foodName'] as String,
  quantity: (e['quantity'] as num).toDouble(),
  unit: e['unit'] as String,
  grams: (e['grams'] as num).toDouble(),
  kcal: (e['kcal'] as num).toInt(),
  proteinG: (e['proteinG'] as num).toDouble(),
  carbsG: (e['carbsG'] as num).toDouble(),
  fatG: (e['fatG'] as num).toDouble(),
  source: nutritionSourceFromName(e['source'] as String?),
  sourceRef: e['sourceRef'] as String,
  origin: foodLogOriginFromName(e['origin'] as String?),
  estimated: e['estimated'] == true,
  mealId: e['mealId'] as String?,
);

EnergyState? _energyFrom(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  return EnergyState(
    maintenanceKcal: (raw['maintenanceKcal'] as num).toInt(),
    source: MaintenanceSource.values.byName(raw['source'] as String),
  );
}

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        json.decode(
              File('test/fixtures/coaching_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  DietState stateFrom(Map<String, dynamic> input) => buildDietState(
    dayKey: '2026-08-30',
    weekday: 7,
    targets: _targetsFrom(input['targets'] as Map<String, dynamic>?),
    planName: 'Cut',
    day: input['day'] == null
        ? null
        : _dayFrom(input['day'] as Map<String, dynamic>),
    consumedMealIds: (input['consumedMealIds'] as List).cast<String>().toSet(),
    log: [
      for (final e in (input['log'] as List).cast<Map<String, dynamic>>())
        _entryFrom(e),
    ],
    energy: _energyFrom(input['energy'] as Map<String, dynamic>?),
  );

  // Convenience for the behaviour tests below: a day with the fixture's plan
  // and whatever overrides a case needs.
  List<CoachingFinding> findingsFor({
    Map<String, dynamic>? targets = const {
      'goal': 'fatLoss',
      'calories': 2200,
      'proteinG': 160,
      'carbsG': 250,
      'fatG': 73,
      'source': 'manual',
    },
    List<Map<String, dynamic>> log = const [],
    List<String> ticked = const [],
    int? hour,
  }) => coachingFindings(
    stateFrom({
      'targets': targets,
      'day': vectors['planDay'],
      'consumedMealIds': ticked,
      'log': log,
    }),
    localHour: hour,
  );

  Map<String, dynamic> entry(Map<String, dynamic> patch) => {
    'id': 'e1',
    'foodId': 'usda:1',
    'foodName': 'Food',
    'quantity': 100,
    'unit': 'g',
    'grams': 100,
    'kcal': 500,
    'proteinG': 20,
    'carbsG': 40,
    'fatG': 15,
    'source': 'usdaFdc',
    'sourceRef': '1',
    'origin': 'logged',
    'estimated': false,
    'mealId': null,
    ...patch,
  };

  List<String> codes(List<CoachingFinding> f) => f.map((x) => x.code).toList();

  test('golden vectors: every case produces the same findings', () {
    for (final spec
        in (vectors['cases'] as List).cast<Map<String, dynamic>>()) {
      final name = spec['name'] as String;
      final findings = coachingFindings(
        stateFrom(spec['input'] as Map<String, dynamic>),
        localHour: (spec['localHour'] as num?)?.toInt(),
      );
      final expected = (spec['expected'] as List).cast<Map<String, dynamic>>();

      expect(findings.length, expected.length, reason: name);
      for (var i = 0; i < expected.length; i++) {
        expect(findings[i].code, expected[i]['code'], reason: name);
        expect(findings[i].kind.name, expected[i]['kind'], reason: name);
        expect(
          findings[i].severity.name,
          expected[i]['severity'],
          reason: name,
        );
        expect(findings[i].text, expected[i]['text'], reason: name);
        expect(
          findings[i].evidence,
          (expected[i]['evidence'] as List).cast<String>(),
          reason: name,
        );
      }
    }
  });

  test('no turn is handed more than three findings', () {
    for (final spec
        in (vectors['cases'] as List).cast<Map<String, dynamic>>()) {
      final findings = coachingFindings(
        stateFrom(spec['input'] as Map<String, dynamic>),
        localHour: (spec['localHour'] as num?)?.toInt(),
      );
      expect(
        findings.length,
        lessThanOrEqualTo(kMaxFindings),
        reason: spec['name'] as String,
      );
    }
  });

  test('every finding names the state it rests on', () {
    // "Why is this being said?" has to be answerable, not asserted.
    for (final spec
        in (vectors['cases'] as List).cast<Map<String, dynamic>>()) {
      for (final finding in coachingFindings(
        stateFrom(spec['input'] as Map<String, dynamic>),
        localHour: (spec['localHour'] as num?)?.toInt(),
      )) {
        expect(finding.evidence, isNotEmpty, reason: finding.code);
        expect(finding.text, isNotEmpty, reason: finding.code);
      }
    }
  });

  test('a target below the safety floor always survives the cap', () {
    final findings = findingsFor(
      targets: const {
        'goal': 'fatLoss',
        'calories': 900,
        'proteinG': 160,
        'carbsG': 250,
        'fatG': 73,
        'source': 'manual',
      },
      log: [entry(const {})],
      hour: 12,
    );
    expect(findings.first.code, 'target_below_safety_floor');
    expect(findings.first.kind, FindingKind.warning);
    expect(findings.first.severity, FindingSeverity.urgent);
  });

  group('the negatives — what the engine must NOT say', () {
    test('a met protein target produces encouragement and no shortfall', () {
      final findings = findingsFor(
        log: [
          entry(const {'kcal': 1900, 'proteinG': 175}),
        ],
        hour: 19,
      );
      expect(codes(findings), contains('protein_met'));
      expect(codes(findings), isNot(contains('protein_shortfall')));
    });

    test('a protein gap early in the day stays quiet', () {
      // There is a whole day left to close it; saying so would be nagging.
      final findings = findingsFor(
        log: [
          entry(const {'kcal': 400, 'proteinG': 25}),
        ],
        hour: 9,
      );
      expect(codes(findings), isNot(contains('protein_shortfall')));
    });

    test('the same gap fires once the calorie budget is running out', () {
      final findings = findingsFor(
        log: [
          entry(const {'kcal': 1850, 'proteinG': 125}),
        ],
        hour: 19,
      );
      final shortfall = findings.firstWhere(
        (f) => f.code == 'protein_shortfall',
      );
      expect(shortfall.kind, FindingKind.recommendation);
      // The recommendation carries its own reason AND the budget it has to
      // work within — the difference between coaching and a slogan.
      expect(shortfall.text, contains('35g short of the 160g protein target'));
      expect(shortfall.text, contains('350 kcal left'));
      expect(shortfall.evidence, contains('remaining.proteinG'));
      expect(shortfall.evidence, contains('remaining.kcal'));
    });

    test('a trivial protein gap is inside the noise and is not raised', () {
      final findings = findingsFor(
        log: [
          entry(const {'kcal': 2100, 'proteinG': 150}),
        ],
        hour: 20,
      );
      expect(codes(findings), isNot(contains('protein_shortfall')));
    });

    test('an empty day produces no overshoot and no shortfall', () {
      final findings = findingsFor(hour: 12);
      expect(codes(findings), ['nothing_logged']);
    });

    test("an empty log is never reported as \"you haven't eaten\"", () {
      for (final hour in [9, 21]) {
        final findings = findingsFor(hour: hour);
        expect(findings.first.text, contains('logged'));
        expect(
          findings.first.text.toLowerCase(),
          isNot(contains("you haven't eaten")),
        );
      }
      // Before evening it's unremarkable; after, it's worth a nudge.
      expect(findingsFor(hour: 9).first.severity, FindingSeverity.info);
      expect(findingsFor(hour: 21).first.severity, FindingSeverity.notable);
    });

    test('with no targets, only the blocker fires — no invented analysis', () {
      final findings = findingsFor(
        targets: null,
        log: [entry(const {})],
        hour: 14,
      );
      expect(codes(findings), ['targets_unset']);
    });

    test('time-dependent rules stay quiet when the hour is unknown', () {
      final findings = findingsFor();
      expect(findings.first.code, 'nothing_logged');
      expect(findings.first.severity, FindingSeverity.info);
    });
  });

  test('a day of ticked meals is qualified, and the qualifier outranks the '
      'readout it qualifies', () {
    // Being wrong about what a figure MEANS is worse than omitting the figure,
    // so the provenance clarifications must survive the cap.
    final findings = findingsFor(ticked: const ['m1-breakfast'], hour: 14);
    expect(codes(findings), contains('consumption_assumed'));
    expect(codes(findings), contains('estimated_values'));
  });

  test('an untracked macro is named so nobody is told they are over on it', () {
    final findings = findingsFor(
      targets: const {
        'goal': 'fatLoss',
        'calories': 2200,
        'proteinG': 160,
        'carbsG': null,
        'fatG': null,
        'source': 'manual',
      },
      log: [entry(const {})],
      hour: 14,
    );
    final untracked = findings.firstWhere((f) => f.code == 'untracked_macros');
    expect(untracked.text, contains('carbs, fat'));
  });
}
