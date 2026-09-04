import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/analysis/maintenance_calibration.dart';
import 'package:zivo/features/diet/domain/body_measures.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/diet_labels.dart';
import 'package:zivo/l10n/l10n.dart';

/// Arabic coverage for the diet vocabulary.
///
/// The diet feature had the densest version of the problem this push keeps
/// running into: enum→word maps stranded in the Flutter-free `domain/` layer,
/// where they could only ever be English. These tests walk **every value of
/// every one of those enums**, so a new goal, activity level or nutrition
/// source that forgets its key fails here rather than silently shipping
/// English to an Arabic reader.
Future<T> _inApp<T>(
  WidgetTester tester,
  Locale locale,
  T Function(BuildContext) body,
) async {
  late T out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          out = body(context);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return out;
}

/// Proper names that stay latin in every language — a translated string may
/// legitimately contain these and nothing else in the roman alphabet.
const _kUntranslatedNames = ['ZIVO', 'USDA', 'FoodData', 'Central', 'BMR'];

void _expectArabic(String value, String what) {
  var stripped = value;
  for (final name in _kUntranslatedNames) {
    stripped = stripped.replaceAll(name, '');
  }
  expect(
    RegExp(r'[A-Za-z]').hasMatch(stripped),
    isFalse,
    reason: '$what still reads "$value" in Arabic',
  );
}

void main() {
  group('every diet enum has an Arabic word', () {
    testWidgets('DietGoal — label and description', (tester) async {
      for (final goal in DietGoal.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => dietGoalText(c, goal)),
          'DietGoal.${goal.name}',
        );
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => dietGoalDetailText(c, goal)),
          'DietGoal.${goal.name} description',
        );
      }
    });

    testWidgets('ActivityLevel — label and description', (tester) async {
      for (final level in ActivityLevel.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => activityText(c, level)),
          'ActivityLevel.${level.name}',
        );
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => activityDetailText(c, level)),
          'ActivityLevel.${level.name} description',
        );
      }
    });

    testWidgets('TargetSource, MacroKind, MissingBodyData, CalibrationGap, DietSource', (tester) async {
      for (final source in TargetSource.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => targetSourceText(c, source)),
          'TargetSource.${source.name}',
        );
      }
      for (final kind in MacroKind.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => macroText(c, kind)),
          'MacroKind.${kind.name}',
        );
      }
      for (final missing in MissingBodyData.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => missingBodyDataText(c, missing)),
          'MissingBodyData.${missing.name}',
        );
      }
      for (final gap in CalibrationGap.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => calibrationGapText(c, gap)),
          'CalibrationGap.${gap.name}',
        );
      }
      for (final source in DietSource.values) {
        _expectArabic(
          await _inApp(tester, const Locale('ar'), (c) => dietSourceText(c, source)),
          'DietSource.${source.name}',
        );
      }
    });

    testWidgets('NutritionSource — except USDA, which is a proper name', (tester) async {
      for (final source in NutritionSource.values) {
        final text = await _inApp(
          tester,
          const Locale('ar'),
          (c) => nutritionSourceText(c, source),
        );
        if (source == NutritionSource.usdaFdc) {
          // A database's name, not copy — it stays latin in both languages.
          expect(text, 'USDA FoodData Central');
        } else {
          _expectArabic(text, 'NutritionSource.${source.name}');
        }
      }
    });
  });

  group('English is unchanged', () {
    testWidgets('the same lookups still read English', (tester) async {
      expect(
        await _inApp(tester, const Locale('en'), (c) => dietGoalText(c, DietGoal.fatLoss)),
        'Fat loss',
      );
      expect(
        await _inApp(tester, const Locale('en'), (c) => macroText(c, MacroKind.protein)),
        'Protein',
      );
      expect(
        await _inApp(tester, const Locale('en'), (c) => activityText(c, ActivityLevel.moderate)),
        'Moderate',
      );
    });
  });

  group("the coaching engine's vocabulary stays English", () {
    test('dietGoalLabel is not localized', () {
      // It is spliced into generated English prose in coaching/rules.dart and
      // quoted as evidence — a half-translated sentence reads worse than an
      // English one. `dietGoalText` is the screen's half; see diet_labels.dart.
      expect(dietGoalLabel(DietGoal.fatLoss), 'Fat loss');
      expect(dietGoalLabel(DietGoal.recomp), 'Recomposition');
    });

    test('activityLabel is not localized', () {
      expect(activityLabel(ActivityLevel.moderate), 'Moderate');
    });

    test('MacroProgress.label stays the engine word while kind carries identity', () {
      const macro = MacroProgress(
        kind: MacroKind.protein,
        label: 'Protein',
        target: 150,
        consumed: 40,
        estimated: false,
      );
      expect(macro.label, 'Protein');
      expect(macro.kind, MacroKind.protein);
    });
  });
}
