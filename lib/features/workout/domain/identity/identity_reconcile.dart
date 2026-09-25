import '../live_session.dart';
import '../workout_plan.dart';
import 'canonical_exercise.dart';
import 'equipment.dart';
import 'exercise_alias.dart';
import 'exercise_library_repository.dart';
import 'exercise_matcher.dart';

/// What one identity pass would write. Additive only: new canonical
/// exercises, new aliases, and slot `exerciseId`s filled in where they were
/// empty. Nothing here deletes, renames or re-points anything that already
/// has an identity, and no session is ever part of it.
class IdentityReconciliation {
  const IdentityReconciliation({
    this.exercises = const [],
    this.aliases = const [],
    this.slotIdentities = const {},
  });

  static const none = IdentityReconciliation();

  /// Canonical exercises to create.
  final List<CanonicalExercise> exercises;

  /// Legacy ids to fold into a canonical exercise, read-side only.
  final List<ExerciseAlias> aliases;

  /// Plan slot id → the canonical exercise it performs, for slots that had
  /// none. Applied to the LIVE copy of each split at write time, so an edit
  /// made in the meantime is never overwritten.
  final Map<String, String> slotIdentities;

  bool get isEmpty =>
      exercises.isEmpty && aliases.isEmpty && slotIdentities.isEmpty;
}

/// The identity migration — and, because it is idempotent, also the sync
/// that keeps new plans and new sessions linked afterwards.
///
/// Every exercise the account has ever planned or logged ends up with a
/// canonical identity, and the same movement across days and splits ends
/// up as ONE identity:
///
/// 1. A slot that already points at an exercise the library lacks (a fresh
///    id from the editor or an in-session swap made offline) gets that
///    exercise created under the id it already uses.
/// 2. Every legacy id still without an identity — a slot never linked, or an
///    id only old sessions remember (a deleted split, an exercise added mid
///    workout) — is matched by name against the library as it grows. Only a
///    **confident** match joins an existing exercise (same movement words,
///    same or no equipment — [matchExercise]); anything less becomes its own
///    exercise. Merging two movements corrupts two histories; a duplicate
///    costs nothing and can be merged later.
/// 3. Each such legacy id gets an alias to its canonical exercise, so every
///    session logged under it reads as that exercise — **on read**, through
///    `ExerciseIdentityResolver`. No session is rewritten, which is what
///    makes all of this reversible.
///
/// Deterministic: the same inputs always produce the same ids
/// ([migratedCanonicalExerciseId]), so two devices running it at once write
/// the same documents rather than duplicates. Running it again on its own
/// output finds nothing to do.
IdentityReconciliation reconcileExerciseIdentities({
  required List<WorkoutPlan> splits,
  required List<LiveSession> sessions,
  required ExerciseLibrary library,
  required DateTime now,
}) {
  final known = Map<String, CanonicalExercise>.of(library.exercises);
  final aliased = {for (final a in library.aliases) a.legacyId};
  final created = <CanonicalExercise>[];
  final aliases = <ExerciseAlias>[];
  final slotIdentities = <String, String>{};

  CanonicalExercise create(String id, String name, String? muscleGroup) {
    final e = CanonicalExercise(
      id: id,
      name: name.trim(),
      equipment: inferEquipmentFromTokens(normalizeExerciseTokens(name)),
      muscleGroup: muscleGroup,
      createdAt: now,
    );
    known[id] = e;
    created.add(e);
    return e;
  }

  final orderedSplits = [...splits]
    ..sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  final slots = [
    for (final split in orderedSplits)
      for (final day in [...split.days]..sort((a, b) => a.order.compareTo(b.order)))
        ...[...day.exercises]..sort((a, b) => a.order.compareTo(b.order)),
  ];

  // 1. Identities slots already point at, but the library doesn't hold.
  for (final slot in slots) {
    final id = slot.exerciseId;
    if (id == null || known.containsKey(id) || aliased.contains(id)) continue;
    if (slot.name.trim().isEmpty) continue;
    create(id, slot.name, slot.muscleGroup);
  }

  // 2. Legacy ids with no identity yet — slots first (the plan is the
  //    better-named source), then ids only history remembers, oldest first.
  final candidates = <_Legacy>[];
  final seen = <String>{};
  for (final slot in slots) {
    if (slot.exerciseId != null || slot.name.trim().isEmpty) continue;
    if (seen.add(slot.id)) {
      candidates.add(_Legacy(slot.id, slot.name, slot.muscleGroup, isSlot: true));
    }
  }
  final orderedSessions = [...sessions]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final historyNames = <String, _Legacy>{};
  for (final session in orderedSessions) {
    for (final e in session.exercises) {
      final id = e.exerciseId;
      if (id.isEmpty || e.name.trim().isEmpty) continue;
      if (seen.contains(id) || known.containsKey(id) || aliased.contains(id)) {
        continue;
      }
      // The newest name wins: a later session reflects any rename.
      historyNames[id] = _Legacy(id, e.name, e.muscleGroup, isSlot: false);
    }
  }
  candidates.addAll(historyNames.values);

  for (final c in candidates) {
    if (c.id.contains('/')) continue; // not a valid document id
    if (!c.isSlot && isCanonicalExerciseId(c.id)) {
      // Already a canonical id (a swap/add saved while the library write
      // failed): the exercise is simply missing its document.
      if (!known.containsKey(c.id)) create(c.id, c.name, c.muscleGroup);
      continue;
    }
    final match = matchExercise(name: c.name, library: known.values);
    final canonical =
        match.confident ??
        create(migratedCanonicalExerciseId(c.id), c.name, c.muscleGroup);
    aliases.add(
      ExerciseAlias(
        legacyId: c.id,
        canonicalId: canonical.id,
        source: AliasSource.migration,
        createdAt: now,
      ),
    );
    aliased.add(c.id);
    if (c.isSlot) slotIdentities[c.id] = canonical.id;
  }

  // 3. A slot whose own id was aliased earlier (a previous pass wrote the
  //    alias but the plan write never landed) just needs pointing.
  final aliasTargets = {for (final a in library.aliases) a.legacyId: a.canonicalId};
  for (final slot in slots) {
    if (slot.exerciseId != null || slotIdentities.containsKey(slot.id)) continue;
    final target = aliasTargets[slot.id];
    if (target != null) slotIdentities[slot.id] = target;
  }

  return IdentityReconciliation(
    exercises: created,
    aliases: aliases,
    slotIdentities: slotIdentities,
  );
}

/// [split] with [slotIdentities] filled into slots that have no identity —
/// never overwriting one a slot already has. Returns [split] itself when
/// nothing applies, so callers can skip the write.
WorkoutPlan applySlotIdentities(
  WorkoutPlan split,
  Map<String, String> slotIdentities,
) {
  var changed = false;
  final days = [
    for (final day in split.days)
      day.copyWith(
        exercises: [
          for (final slot in day.exercises)
            if (slot.exerciseId == null && slotIdentities.containsKey(slot.id))
              () {
                changed = true;
                return slot.copyWith(exerciseId: slotIdentities[slot.id]);
              }()
            else
              slot,
        ],
      ),
  ];
  return changed ? split.copyWith(days: days) : split;
}

class _Legacy {
  const _Legacy(this.id, this.name, this.muscleGroup, {required this.isSlot});
  final String id;
  final String name;
  final String? muscleGroup;
  final bool isSlot;
}
