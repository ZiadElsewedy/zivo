import 'logged_set.dart';
import 'session_exercise.dart';
import 'set_type.dart';

/// Muscle groups treated as small/isolation work — clamped to a shorter base
/// rest even at low rep counts, since they don't tax recovery the way a heavy
/// compound lift does. Matched as a case-insensitive substring against the
/// exercise's free-text `muscleGroup`, so "Biceps", "biceps (isolation)", and
/// "Rear delts" all match.
const Set<String> _smallMuscleGroups = {
  'biceps',
  'triceps',
  'calves',
  'calf',
  'abs',
  'core',
  'forearms',
  'forearm',
  'delts',
  'shoulders',
};

bool _isSmallMuscleGroup(String? muscleGroup) {
  if (muscleGroup == null) return false;
  final normalized = muscleGroup.toLowerCase();
  return _smallMuscleGroups.any(normalized.contains);
}

/// The automatic, no-config rest window for a just-finished set — shorter for
/// isolation/accessory work and for later sets within the same exercise,
/// always under 2 minutes. This is the live session's default rest length in
/// place of the plan's stored `restSeconds`; the user can still nudge it
/// ±15s or skip it entirely.
///
/// - Base, by intensity ([repTargetMin], the set's rep-target floor — lower
///   reps read as higher intensity): <=6 reps → 115s, 7–12 → 90s, >12 → 60s.
/// - Small/isolation [muscleGroup]s clamp that base down to <=75s; large
///   compound groups (legs, back, chest, ...) keep the full base.
/// - Decays 10s per subsequent working set ([workingSetIndex], 0-based —
///   see [workingSetIndexOf]), floored at 45s.
/// - Hard-capped at 115s regardless (the base already never exceeds it, but
///   this keeps the "<2min, always" guarantee explicit).
int smartRestSeconds({
  required int repTargetMin,
  String? muscleGroup,
  required int workingSetIndex,
}) {
  var base = switch (repTargetMin) {
    <= 6 => 115,
    <= 12 => 90,
    _ => 60,
  };
  if (_isSmallMuscleGroup(muscleGroup) && base > 75) {
    base = 75;
  }
  final decayed = base - (10 * workingSetIndex);
  final floored = decayed < 45 ? 45 : decayed;
  return floored > 115 ? 115 : floored;
}

/// [set]'s 0-based position among [exercise]'s *working*-type sets (the first
/// working set is index 0). Non-working sets (warmup/dropset/failure — not
/// yet driven by this policy) resolve to 0 rather than throwing, since they
/// aren't counted in the working-set sequence at all.
int workingSetIndexOf(SessionExercise exercise, LoggedSet set) {
  var index = 0;
  for (final s in exercise.sets) {
    if (s.id == set.id) return s.type == SetType.working ? index : 0;
    if (s.type == SetType.working) index++;
  }
  return index;
}
