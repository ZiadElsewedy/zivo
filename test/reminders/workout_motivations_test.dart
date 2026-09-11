import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/domain/workout_motivations.dart';

void main() {
  group('pickWorkoutMotivation', () {
    test('is deterministic in the seed', () {
      expect(
        pickWorkoutMotivation(seed: 7),
        pickWorkoutMotivation(seed: 7),
      );
    });

    test('rotates from one seed to the next', () {
      final lines = {
        for (var seed = 0; seed < 8; seed++) pickWorkoutMotivation(seed: seed),
      };
      expect(lines.length, greaterThan(1));
    });

    test('a negative seed still resolves to a real line', () {
      // A hash code can be negative; the pick must stay in range.
      final line = pickWorkoutMotivation(seed: -13);
      expect(workoutMotivationsFor(MotivationTone.gentle, 'en'), contains(line));
    });

    test('the tone selects its own list', () {
      const seed = 3;
      final gentle = pickWorkoutMotivation(seed: seed, tone: MotivationTone.gentle);
      final tough = pickWorkoutMotivation(seed: seed, tone: MotivationTone.toughLove);
      expect(workoutMotivationsFor(MotivationTone.gentle, 'en'), contains(gentle));
      expect(workoutMotivationsFor(MotivationTone.toughLove, 'en'), contains(tough));
    });

    test('picks the Arabic line for an ar locale, aligned with English', () {
      for (final tone in MotivationTone.values) {
        const seed = 4;
        final en = pickWorkoutMotivation(seed: seed, languageCode: 'en', tone: tone);
        final ar = pickWorkoutMotivation(seed: seed, languageCode: 'ar', tone: tone);
        final enIndex = workoutMotivationsFor(tone, 'en').indexOf(en);
        expect(ar, workoutMotivationsFor(tone, 'ar')[enIndex]);
      }
    });

    test('every tone keeps its two language lists index-aligned', () {
      for (final tone in MotivationTone.values) {
        expect(
          workoutMotivationsFor(tone, 'en'),
          hasLength(workoutMotivationsFor(tone, 'ar').length),
          reason: 'tone $tone must have matching en/ar list lengths',
        );
      }
    });

    test('MotivationTone.fromName falls back to gentle for the unknown', () {
      expect(MotivationTone.fromName('hype'), MotivationTone.hype);
      expect(MotivationTone.fromName('mystery'), MotivationTone.gentle);
      expect(MotivationTone.fromName(null), MotivationTone.gentle);
    });
  });
}
