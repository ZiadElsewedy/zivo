import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/analysis/maintenance_calibration.dart';
import 'package:zivo/features/diet/domain/body_measures.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';

final _now = DateTime(2026, 8, 31);

BodyWeightEntry _weighIn(double kg, DateTime at) =>
    BodyWeightEntry(id: at.toIso8601String(), weightKg: kg, loggedAt: at);

/// [count] consecutive days of [kcal], starting [startDaysAgo] before [_now].
List<DailyIntake> _intake({
  required int count,
  required int kcal,
  int startDaysAgo = 28,
}) => [
  for (var i = 0; i < count; i++)
    DailyIntake(
      dayKey: _key(_now.subtract(Duration(days: startDaysAgo - i))),
      kcal: kcal,
    ),
];

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  group('calibrateMaintenance', () {
    test('measures maintenance below intake when weight went up', () {
      // 28 days, 2,600 kcal a day, +0.8 kg. Some of what they ate went into
      // storage, so their true maintenance is BELOW what they ate:
      // 0.8 kg × 7700 / 28 = 220 kcal a day of surplus → 2,380.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(82.8, _now),
        ],
        intake: _intake(count: 28, kcal: 2600),
        now: _now,
      );

      expect(result.isMeasured, isTrue);
      final measured = result.measured!;
      expect(measured.maintenanceKcal, 2380);
      expect(measured.averageIntakeKcal, 2600);
      expect(measured.weightChangeKg, closeTo(0.8, 0.001));
      expect(measured.days, 28);
      expect(measured.loggedDays, 28);
      expect(measured.coverage, 1.0);
      expect(measured.observedKgPerWeek, closeTo(0.2, 0.001));
    });

    test('measures maintenance above intake when weight came down', () {
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(81.0, _now),
        ],
        intake: _intake(count: 28, kcal: 2000),
        now: _now,
      );

      // −1 kg over 28 days = 275 kcal/day of deficit → maintenance 2,275.
      expect(result.measured!.maintenanceKcal, 2275);
      expect(result.measured!.weightChangeKg, closeTo(-1.0, 0.001));
    });

    test('holding steady measures maintenance as what they ate', () {
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(82.0, _now),
        ],
        intake: _intake(count: 28, kcal: 2450),
        now: _now,
      );

      expect(result.measured!.maintenanceKcal, 2450);
    });

    test('refuses with fewer than two weigh-ins', () {
      final result = calibrateMaintenance(
        weighIns: [_weighIn(82, _now)],
        intake: _intake(count: 28, kcal: 2600),
        now: _now,
      );

      expect(result.isMeasured, isFalse);
      expect(result.gap, CalibrationGap.needsWeighIns);
    });

    test('refuses a window too short to outlast water weight', () {
      // Ten days: bodyweight moves a kilo on hydration alone over that
      // stretch, so the "measurement" would mostly be noise.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 10))),
          _weighIn(81.2, _now),
        ],
        intake: _intake(count: 11, kcal: 2600, startDaysAgo: 10),
        now: _now,
      );

      expect(result.gap, CalibrationGap.needsLongerWindow);
    });

    test('refuses when too little of the window was logged', () {
      // 28 days, only 12 of them logged — 43% coverage. The average would be
      // speaking for sixteen days it never saw.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(82.8, _now),
        ],
        intake: _intake(count: 12, kcal: 2600),
        now: _now,
      );

      expect(result.gap, CalibrationGap.needsMoreLoggedDays);
    });

    test('refuses a short window even at full coverage', () {
      // 14 days all logged clears the fraction, but nine logged days is too
      // thin an average whatever percentage it represents.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 14))),
          _weighIn(82.4, _now),
        ],
        intake: _intake(count: 9, kcal: 2600, startDaysAgo: 14),
        now: _now,
      );

      expect(result.gap, CalibrationGap.needsMoreLoggedDays);
    });

    test('logged days outside the window do not count toward it', () {
      // Plenty of logging, but almost all of it BEFORE the first weigh-in —
      // a period the weight change says nothing about.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 20))),
          _weighIn(82.5, _now),
        ],
        intake: _intake(count: 30, kcal: 2600, startDaysAgo: 60),
        now: _now,
      );

      expect(result.gap, CalibrationGap.needsMoreLoggedDays);
    });

    test('the window is the weigh-ins, whatever order they arrive in', () {
      final ordered = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(82.8, _now),
        ],
        intake: _intake(count: 28, kcal: 2600),
        now: _now,
      );
      final reversed = calibrateMaintenance(
        weighIns: [
          _weighIn(82.8, _now),
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
        ],
        intake: _intake(count: 28, kcal: 2600),
        now: _now,
      );

      expect(
        reversed.measured!.maintenanceKcal,
        ordered.measured!.maintenanceKcal,
      );
    });

    test('the widest pair of weigh-ins defines the window', () {
      // Three weigh-ins: the middle one must not shorten the window.
      final result = calibrateMaintenance(
        weighIns: [
          _weighIn(82.0, _now.subtract(const Duration(days: 28))),
          _weighIn(82.5, _now.subtract(const Duration(days: 14))),
          _weighIn(82.8, _now),
        ],
        intake: _intake(count: 28, kcal: 2600),
        now: _now,
      );

      expect(result.measured!.days, 28);
      expect(result.measured!.maintenanceKcal, 2380);
    });
  });

  group('maintenanceDisagrees', () {
    test('only flags a gap big enough to mean something', () {
      expect(maintenanceDisagrees(2400, 2500), isFalse);
      expect(maintenanceDisagrees(2400, 2550), isTrue);
      expect(maintenanceDisagrees(2550, 2400), isTrue);
    });
  });

  group('where a maintenance figure comes from', () {
    BodyMeasures measures({int? stated, int? measured}) => BodyMeasures(
      weightKg: 82,
      weighedAt: _now,
      heightCm: 178,
      age: 30,
      sex: TargetSex.male,
      activity: ActivityLevel.moderate,
      statedMaintenanceKcal: stated,
      measuredMaintenanceKcal: measured,
    );

    test('a measurement replaces the equation', () {
      final m = measures(measured: 2950);

      expect(m.maintenanceKcal, 2950);
      expect(m.maintenanceSource, MaintenanceSource.measured);
      // The equation is still available, so the two can be compared.
      expect(m.estimatedMaintenanceKcal, 2771);
    });

    test("a measurement does NOT overrule what the user said themselves", () {
      final m = measures(stated: 2700, measured: 2950);

      expect(m.maintenanceKcal, 2700);
      expect(m.maintenanceSource, MaintenanceSource.stated);
    });

    test('with neither, the equation stands and says so', () {
      final m = measures();

      expect(m.maintenanceKcal, 2771);
      expect(m.maintenanceSource, MaintenanceSource.estimated);
      expect(
        maintenanceSourceLabel(m.maintenanceSource),
        'an estimate from your body data',
      );
    });
  });
}
