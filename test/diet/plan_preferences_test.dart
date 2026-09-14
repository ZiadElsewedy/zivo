import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';

void main() {
  group('splitNaturalFoodList', () {
    test('splits a natural sentence on commas and conjunctions', () {
      expect(
        splitNaturalFoodList("I don't like fish, broccoli, or cottage cheese"),
        ['fish', 'broccoli', 'cottage cheese'],
      );
    });

    test('splits "x and y"', () {
      expect(splitNaturalFoodList('peanuts and shellfish'),
          ['peanuts', 'shellfish']);
    });

    test('strips leading allergy/dislike filler', () {
      expect(splitNaturalFoodList('allergic to peanuts'), ['peanuts']);
      expect(splitNaturalFoodList('no dairy'), ['dairy']);
    });

    test('drops blanks and de-duplicates case-insensitively', () {
      expect(splitNaturalFoodList('Fish, fish, , eggs'), ['Fish', 'eggs']);
    });

    test('empty in, empty out', () {
      expect(splitNaturalFoodList('   '), isEmpty);
    });
  });

  group('toPayload', () {
    test('folds eating habits and schedule into the notes field', () {
      const prefs = PlanPreferences(
        mealsPerDay: 4,
        eatingHabits: 'eggs and bread for breakfast',
        scheduleNotes: 'train at 6am',
      );
      final notes = prefs.toPayload()['notes'] as String;
      expect(notes, contains('eggs and bread for breakfast'));
      expect(notes, contains('train at 6am'));
    });

    test('omits notes entirely when nothing free-text was given', () {
      const prefs = PlanPreferences(mealsPerDay: 3);
      expect(prefs.toPayload().containsKey('notes'), isFalse);
    });

    test('sends empty avoid/allergies rather than omitting them', () {
      const prefs = PlanPreferences(mealsPerDay: 3);
      final payload = prefs.toPayload();
      expect(payload['avoid'], isEmpty);
      expect(payload['allergies'], isEmpty);
    });
  });
}
