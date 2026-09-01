import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/analysis/maintenance_calibration.dart';
import 'package:zivo/features/diet/domain/body_measures.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';

/// The shared fixture `functions/diet/energy.test.js` also runs.
///
/// The Diet screen computes what the user burns in Dart; the coach computes it
/// in JavaScript. If the two drift, the app tells someone their target is 300
/// over maintenance while the coach congratulates them for hitting it — so the
/// two implementations are pinned against one file rather than against each
/// other's comments.
void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        json.decode(
              File('test/fixtures/energy_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test('golden vectors: every calibration case measures the same', () {
    for (final spec
        in (vectors['calibration'] as List).cast<Map<String, dynamic>>()) {
      final name = spec['name'] as String;
      final input = spec['input'] as Map<String, dynamic>;
      final expected = spec['expected'] as Map<String, dynamic>;

      final result = calibrateMaintenance(
        weighIns: [
          for (final w
              in (input['weighIns'] as List).cast<Map<String, dynamic>>())
            BodyWeightEntry(
              id: '${w['loggedAtMs']}',
              weightKg: (w['weightKg'] as num).toDouble(),
              loggedAt: DateTime.fromMillisecondsSinceEpoch(
                (w['loggedAtMs'] as num).toInt(),
                isUtc: true,
              ).toUtc(),
            ),
        ],
        intake: [
          for (final d
              in (input['intake'] as List).cast<Map<String, dynamic>>())
            DailyIntake(
              dayKey: d['dayKey'] as String,
              kcal: (d['kcal'] as num).toInt(),
            ),
        ],
        now: DateTime.fromMillisecondsSinceEpoch(
          (vectors['anchorMs'] as num).toInt(),
          isUtc: true,
        ),
      );

      final measured = expected['measured'] as Map<String, dynamic>?;
      if (measured == null) {
        expect(result.isMeasured, isFalse, reason: name);
        expect(result.gap!.name, expected['gap'], reason: name);
      } else {
        expect(result.isMeasured, isTrue, reason: name);
        expect(
          result.measured!.maintenanceKcal,
          measured['maintenanceKcal'],
          reason: name,
        );
        expect(
          result.measured!.averageIntakeKcal,
          measured['averageIntakeKcal'],
          reason: name,
        );
        expect(
          result.measured!.weightChangeKg,
          closeTo((measured['weightChangeKg'] as num).toDouble(), 0.05),
          reason: name,
        );
        expect(result.measured!.days, measured['days'], reason: name);
        expect(
          result.measured!.loggedDays,
          measured['loggedDays'],
          reason: name,
        );
      }
    }
  });

  test('golden vectors: every maintenance case resolves the same', () {
    for (final spec
        in (vectors['energy'] as List).cast<Map<String, dynamic>>()) {
      final name = spec['name'] as String;
      final input = spec['input'] as Map<String, dynamic>;
      final expected = spec['expected'] as Map<String, dynamic>?;

      final rawProfile = input['profile'] as Map<String, dynamic>?;
      final weightKg = (input['weightKg'] as num?)?.toDouble();
      final age = (input['age'] as num?)?.toInt();
      final measured = (input['measuredMaintenanceKcal'] as num?)?.toInt();

      // The Dart side expresses "no maintenance" as an incomplete
      // `BodyMeasures` — the same absence, reached the same way.
      if (rawProfile == null || weightKg == null || age == null) {
        expect(expected, isNull, reason: name);
        continue;
      }
      final profile = BodyProfile(
        heightCm: (rawProfile['heightCm'] as num).toDouble(),
        sex: TargetSex.values.byName(rawProfile['sex'] as String),
        activity: ActivityLevel.values.byName(rawProfile['activity'] as String),
        statedMaintenanceKcal: (rawProfile['statedMaintenanceKcal'] as num?)
            ?.toInt(),
        updatedAt: DateTime(2026, 8, 31),
      );
      final measures = BodyMeasures(
        weightKg: weightKg,
        weighedAt: DateTime(2026, 8, 31),
        heightCm: profile.heightCm,
        age: age,
        sex: profile.sex,
        activity: profile.activity,
        statedMaintenanceKcal: profile.statedMaintenanceKcal,
        measuredMaintenanceKcal: measured,
      );

      expect(expected, isNotNull, reason: name);
      expect(
        measures.maintenanceKcal,
        expected!['maintenanceKcal'],
        reason: name,
      );
      expect(measures.maintenanceSource.name, expected['source'], reason: name);
    }
  });
}
