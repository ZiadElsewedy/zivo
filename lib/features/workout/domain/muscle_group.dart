/// Muscle groups treated as small/isolation work — they don't tax recovery
/// or load progression the way a heavy compound lift does, so both the rest
/// policy (shorter rest) and the progression policy (smaller weight jumps)
/// key off this same classification. Matched as a case-insensitive substring
/// against the exercise's free-text `muscleGroup`, so "Biceps",
/// "biceps (isolation)", and "Rear delts" all match.
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

bool isSmallMuscleGroup(String? muscleGroup) {
  if (muscleGroup == null) return false;
  final normalized = muscleGroup.toLowerCase();
  return _smallMuscleGroups.any(normalized.contains);
}
