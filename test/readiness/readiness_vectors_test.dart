import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/readiness/domain/readiness.dart';

/// The Dart half of the shared readiness golden vectors. The SAME
/// `test/fixtures/readiness_vectors.json` is run by `functions/ai/readiness.test.js`,
/// so the Today card's engine and the AI coach's mirror cannot drift.
Map<String, dynamic> _serialize(Readiness? r) {
  if (r == null) return const {'expected': null};
  return {
    'verdict': r.verdict.name,
    'factors': [
      for (final f in r.factors)
        {
          'kind': f.kind.name,
          'direction': f.direction.name,
          if (f.sleepDurationMinutes != null)
            'sleepDurationMinutes': f.sleepDurationMinutes,
          if (f.sleepDeltaMinutes != null)
            'sleepDeltaMinutes': f.sleepDeltaMinutes,
          if (f.deloadExerciseCount != null)
            'deloadExerciseCount': f.deloadExerciseCount,
          if (f.restDays != null) 'restDays': f.restDays,
          if (f.weightChangeKg != null) 'weightChangeKg': f.weightChangeKg,
        },
    ],
  };
}

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        jsonDecode(
              File('test/fixtures/readiness_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('golden vectors: every case matches the shared engine', () {
    for (final raw in (vectors['cases'] as List)) {
      final vec = raw as Map<String, dynamic>;
      final input = (vec['input'] as Map).cast<String, dynamic>();
      final result = readinessFromSignals(
        sleepDurationMinutes: input['sleepDurationMinutes'] as int?,
        sleepTargetMinutes: input['sleepTargetMinutes'] as int?,
        stalledCount: (input['stalledCount'] as int?) ?? 0,
        overallStatusRegressing:
            (input['overallStatusRegressing'] as bool?) ?? false,
        lastSessionDaysAgo: input['lastSessionDaysAgo'] as int?,
        weightChangeKg: (input['weightChangeKg'] as num?)?.toDouble(),
        hasWeighIn: (input['hasWeighIn'] as bool?) ?? false,
      );

      final expected = vec['expected'];
      if (expected == null) {
        expect(result, isNull, reason: '${vec['name']}: expected the gate');
        continue;
      }
      expect(
        _serialize(result),
        equals((expected as Map).cast<String, dynamic>()),
        reason: vec['name'] as String,
      );
    }
  });
}
