import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/progress_comparison.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';

LoggedSet _done({required int reps, double? weightKg}) => LoggedSet(
  id: 'prev',
  target: RepTarget.fixed(reps),
  outcome: SetOutcome.completed,
  actualReps: reps,
  actualWeightKg: weightKg,
);

void main() {
  group('compareToLastTime — no real comparison available', () {
    test('null previous (never trained) → null', () {
      final result = compareToLastTime(previous: null, actualReps: 8, actualWeightKg: 60);
      expect(result, isNull);
    });

    test('previous never logged (no actualReps) → null', () {
      final unlogged = const LoggedSet(id: 'x', target: RepTarget.fixed(8));
      final result = compareToLastTime(previous: unlogged, actualReps: 8, actualWeightKg: 60);
      expect(result, isNull);
    });

    test('no rep count entered yet for today → null', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 60),
        actualReps: null,
        actualWeightKg: 60,
      );
      expect(result, isNull);
    });
  });

  group('compareToLastTime — matched', () {
    test('identical reps and weight → matched, 0% overall', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 60),
        actualReps: 8,
        actualWeightKg: 60,
      );
      expect(result!.verdict, ProgressVerdict.matched);
      expect(result.overallChangePercent, 0);
      expect(result.repsChangePercent, 0);
      expect(result.weightChangeKg, 0);
      expect(result.volumeChangePercent, 0);
    });

    test('identical reps, both bodyweight (no weight either side) → matched', () {
      final result = compareToLastTime(previous: _done(reps: 12), actualReps: 12, actualWeightKg: null);
      expect(result!.verdict, ProgressVerdict.matched);
      expect(result.weightChangeKg, isNull);
      expect(result.volumeChangePercent, isNull);
    });
  });

  group('compareToLastTime — progressing (weighted)', () {
    test('more reps, same weight → volume up → progressing', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 60),
        actualReps: 10,
        actualWeightKg: 60,
      );
      expect(result!.verdict, ProgressVerdict.progressing);
      expect(result.repsChangePercent, closeTo(25, 0.001)); // 8 → 10
      expect(result.weightChangeKg, 0);
      // volume 480 → 600 = +25%
      expect(result.volumeChangePercent, closeTo(25, 0.001));
      expect(result.overallChangePercent, closeTo(25, 0.001));
    });

    test('same reps, heavier weight → volume up → progressing', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 60),
        actualReps: 8,
        actualWeightKg: 65,
      );
      expect(result!.verdict, ProgressVerdict.progressing);
      expect(result.weightChangeKg, 5);
      // volume 480 → 520 = +8.333...%
      expect(result.volumeChangePercent, closeTo(8.33, 0.01));
    });

    test('fewer reps but much heavier weight can still net progressing on volume', () {
      final result = compareToLastTime(
        previous: _done(reps: 10, weightKg: 40),
        actualReps: 6,
        actualWeightKg: 80,
      );
      // volume 400 → 480 = +20%, even though reps dropped
      expect(result!.repsChangePercent, closeTo(-40, 0.001));
      expect(result.volumeChangePercent, closeTo(20, 0.001));
      expect(result.overallChangePercent, closeTo(20, 0.001));
      expect(result.verdict, ProgressVerdict.progressing);
    });
  });

  group('compareToLastTime — down (weighted)', () {
    test('fewer reps, same weight → volume down → down', () {
      final result = compareToLastTime(
        previous: _done(reps: 10, weightKg: 50),
        actualReps: 8,
        actualWeightKg: 50,
      );
      expect(result!.verdict, ProgressVerdict.down);
      expect(result.repsChangePercent, closeTo(-20, 0.001));
      // volume 500 → 400 = -20%
      expect(result.volumeChangePercent, closeTo(-20, 0.001));
    });

    test('same reps, lighter weight → volume down → down', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 60),
        actualReps: 8,
        actualWeightKg: 55,
      );
      expect(result!.verdict, ProgressVerdict.down);
      expect(result.weightChangeKg, -5);
    });
  });

  group('compareToLastTime — bodyweight (no weight tracked either side)', () {
    test('more reps → falls back to reps % for volume/overall → progressing', () {
      final result = compareToLastTime(previous: _done(reps: 12), actualReps: 15, actualWeightKg: null);
      expect(result!.verdict, ProgressVerdict.progressing);
      expect(result.volumeChangePercent, isNull);
      expect(result.weightChangeKg, isNull);
      expect(result.repsChangePercent, closeTo(25, 0.001));
      expect(result.overallChangePercent, closeTo(25, 0.001));
    });

    test('fewer reps → down', () {
      final result = compareToLastTime(previous: _done(reps: 12), actualReps: 10, actualWeightKg: null);
      expect(result!.verdict, ProgressVerdict.down);
      expect(result.overallChangePercent, closeTo(-16.67, 0.01));
    });
  });

  group('compareToLastTime — mixed weight tracking (one side only)', () {
    test('previous had a weight, today logged none → weight/volume deltas null, judged on reps', () {
      final result = compareToLastTime(
        previous: _done(reps: 8, weightKg: 20),
        actualReps: 9,
        actualWeightKg: null,
      );
      expect(result!.weightChangeKg, isNull);
      expect(result.volumeChangePercent, isNull);
      expect(result.overallChangePercent, closeTo(12.5, 0.001)); // reps 8 → 9
      expect(result.verdict, ProgressVerdict.progressing);
    });
  });
}
