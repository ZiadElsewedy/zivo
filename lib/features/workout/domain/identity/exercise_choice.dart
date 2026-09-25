import 'canonical_exercise.dart';
import 'equipment.dart';
import '../planned_exercise.dart';
import '../workout_plan.dart';
import 'exercise_matcher.dart';

/// An exercise picked for a workout — from the library, from the plan, or
/// typed by name — before it has been given an identity.
///
/// [canonicalId] is set when the pick already names a canonical exercise; a
/// typed name has none, and [resolveExerciseChoice] decides whether it is one
/// the user already has.
class ExerciseChoice {
  const ExerciseChoice({
    this.canonicalId,
    required this.name,
    this.muscleGroup,
    this.equipment,
  });

  final String? canonicalId;
  final String name;
  final String? muscleGroup;
  final Equipment? equipment;
}

/// The identity a [choice] resolves to, and — when it named no exercise the
/// user already has — the new [CanonicalExercise] to save for it.
///
/// A pick that already carries an id keeps it. A typed name is linked to an
/// existing exercise only on a *confident* match (same movement words, same
/// or no equipment — see [matchExercise]); anything less becomes a new
/// exercise, because merging two different movements corrupts both
/// histories while a duplicate can always be merged later.
({String canonicalId, CanonicalExercise? created}) resolveExerciseChoice(
  ExerciseChoice choice, {
  required Iterable<CanonicalExercise> library,
  required String Function() newId,
  required DateTime now,
}) {
  final existing = choice.canonicalId;
  if (existing != null) return (canonicalId: existing, created: null);
  final match = matchExercise(
    name: choice.name,
    equipment: choice.equipment,
    library: library,
  );
  final confident = match.confident;
  if (confident != null) return (canonicalId: confident.id, created: null);
  final tokens = normalizeExerciseTokens(choice.name);
  final created = CanonicalExercise(
    id: newId(),
    name: choice.name.trim(),
    equipment: choice.equipment ?? inferEquipmentFromTokens(tokens),
    muscleGroup: choice.muscleGroup,
    createdAt: now,
  );
  return (canonicalId: created.id, created: created);
}

/// Everything the user could pick when adding or swapping an exercise: each
/// of their canonical exercises and every exercise in their splits, **one
/// row per identity** (a lift on three days is one choice, not three),
/// named by the library when it has a name and sorted by name.
///
/// [exclude] drops identities already in the way — the exercise being
/// swapped out, say. Slot ids are resolved through [canonicalIdOf] so a
/// slot aliased onto a library exercise doesn't show up twice.
List<ExerciseChoice> exerciseCandidates({
  required Iterable<WorkoutPlan> splits,
  required Map<String, CanonicalExercise> library,
  required String Function(String id) canonicalIdOf,
  Set<String> exclude = const {},
}) {
  final byId = <String, ExerciseChoice>{};
  for (final c in library.values) {
    // One merged into another is that other one now.
    if (c.name.trim().isEmpty || canonicalIdOf(c.id) != c.id) continue;
    byId[c.id] = ExerciseChoice(
      canonicalId: c.id,
      name: c.name,
      muscleGroup: c.muscleGroup,
      equipment: c.equipment,
    );
  }
  for (final split in splits) {
    for (final day in split.days) {
      for (final slot in day.exercises) {
        final id = canonicalIdOf(slot.canonicalId);
        if (slot.name.trim().isEmpty) continue;
        byId.putIfAbsent(
          id,
          () => ExerciseChoice(
            canonicalId: id,
            name: slot.name,
            muscleGroup: slot.muscleGroup,
          ),
        );
      }
    }
  }
  // One row per MOVEMENT, too: before the migration has linked everything,
  // "Cable Lateral Raise" on two days is two ids with one name. Names that
  // are confidently the same exercise collapse into the first seen (library
  // entries come first, so the canonical name wins); anything short of
  // confident stays its own row, exactly as identity itself would treat it.
  final kept = <ExerciseChoice>[];
  final signatures = <ExerciseSignature>[];
  for (final e in byId.entries) {
    if (exclude.contains(e.key)) continue;
    final sig = ExerciseSignature.of(e.value.name, equipment: e.value.equipment);
    final dupe = signatures.indexWhere(
      (other) => other.compare(sig) == SignatureMatch.same,
    );
    if (dupe >= 0) {
      // Keep the richer row: one that knows its muscle group.
      if (kept[dupe].muscleGroup == null && e.value.muscleGroup != null) {
        kept[dupe] = ExerciseChoice(
          canonicalId: kept[dupe].canonicalId,
          name: kept[dupe].name,
          muscleGroup: e.value.muscleGroup,
          equipment: kept[dupe].equipment,
        );
      }
      continue;
    }
    kept.add(e.value);
    signatures.add(sig);
  }
  return kept
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The identity an edited plan slot should carry.
///
/// Editing a slot keeps the exercise it performs — renaming included — so
/// its history stays with it. The one exception is a rename to a **different
/// movement** ([isDifferentMovement]: other equipment, another variation, or
/// nothing in common): that slot now performs another exercise, and keeping
/// the old identity would pour the new movement's numbers into the old
/// one's history. It then gets the identity of the exercise it names — one
/// the user already has on a confident match, else a new one.
///
/// The old history is untouched either way: sessions keep the id they were
/// logged with, and the identity sync folds a slot id that only history
/// still remembers into an exercise of its own.
({String? exerciseId, CanonicalExercise? created}) identityAfterEdit({
  required PlannedExercise before,
  required PlannedExercise after,
  required Iterable<CanonicalExercise> library,
  required String Function() newId,
  required DateTime now,
}) {
  if (!isDifferentMovement(before.name, after.name)) {
    return (exerciseId: before.exerciseId, created: null);
  }
  final resolved = resolveExerciseChoice(
    ExerciseChoice(name: after.name, muscleGroup: after.muscleGroup),
    library: library,
    newId: newId,
    now: now,
  );
  return (exerciseId: resolved.canonicalId, created: resolved.created);
}
