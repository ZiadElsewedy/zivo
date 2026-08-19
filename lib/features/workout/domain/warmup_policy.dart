import 'muscle_group.dart';

/// The minimum working weight a compound lift must carry before a warm-up
/// ramp is worth generating — below this, a couple of light ramp-up sets add
/// friction without meaningfully reducing injury risk or improving the work
/// set.
const double _minQualifyingWeightKg = 40;

/// The floor every ramp step rounds down to — an empty barbell.
const double _barKg = 20;

/// The full ramp scheme, heaviest-qualifying-load steps last. Reps drop as
/// the percentage of the working weight climbs.
const List<({double pct, int reps})> _steps = [
  (pct: 0.4, reps: 8),
  (pct: 0.6, reps: 5),
  (pct: 0.8, reps: 3),
  (pct: 0.9, reps: 1),
];

/// The automatic warm-up ramp before a heavy compound lift's first working
/// set — a short ladder of lighter, higher-rep sets that rehearses the
/// movement and primes the joints, with no configuration required.
///
/// Empty for isolation/small-muscle-group work (you don't ramp curls — see
/// [isSmallMuscleGroup]) and for anything under [_minQualifyingWeightKg],
/// where a ramp adds friction without real benefit.
///
/// Otherwise returns 2–4 steps (more steps for heavier loads): ~40%×8,
/// ~60%×5, always; ~80%×3 once the working weight clears 60kg; ~90%×1 added
/// only past 100kg, where the jump to full load is largest. Every step's
/// weight is rounded to the nearest 2.5kg and floored at [_barKg].
List<({double weightKg, int reps})> warmupRampFor({
  required double workingWeightKg,
  String? muscleGroup,
}) {
  if (isSmallMuscleGroup(muscleGroup)) return const [];
  if (workingWeightKg < _minQualifyingWeightKg) return const [];

  final count = workingWeightKg > 100 ? 4 : (workingWeightKg >= 60 ? 3 : 2);
  return [
    for (final step in _steps.take(count))
      (weightKg: _roundWeight(workingWeightKg * step.pct), reps: step.reps),
  ];
}

double _roundWeight(double raw) {
  final rounded = (raw / 2.5).round() * 2.5;
  return rounded < _barKg ? _barKg : rounded;
}
