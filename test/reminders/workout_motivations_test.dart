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
      // Consecutive days should not all land on the same line.
      final lines = {
        for (var seed = 0; seed < kWorkoutMotivationsEn.length; seed++)
          pickWorkoutMotivation(seed: seed),
      };
      expect(lines.length, greaterThan(1));
    });

    test('a negative seed still resolves to a real line', () {
      // A hash code can be negative; the pick must stay in range.
      final line = pickWorkoutMotivation(seed: -13);
      expect(kWorkoutMotivationsEn, contains(line));
    });

    test('picks the Arabic line for an ar locale, index-aligned with English', () {
      const seed = 4;
      final en = pickWorkoutMotivation(seed: seed, languageCode: 'en');
      final ar = pickWorkoutMotivation(seed: seed, languageCode: 'ar');
      final enIndex = kWorkoutMotivationsEn.indexOf(en);
      expect(ar, kWorkoutMotivationsAr[enIndex]);
    });

    test('the two language lists stay index-aligned', () {
      expect(kWorkoutMotivationsEn, hasLength(kWorkoutMotivationsAr.length));
    });
  });
}
