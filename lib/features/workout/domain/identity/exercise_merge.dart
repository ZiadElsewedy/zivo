import 'canonical_exercise.dart';
import 'exercise_alias.dart';
import 'exercise_library_repository.dart';
import 'exercise_matcher.dart';

/// Two exercises whose names say they *might* be the same movement — "Hammer
/// Curl" and "Hammer Dumbbell Curl", where one name states the equipment and
/// the other doesn't. The migration never merges these on its own (a wrong
/// merge corrupts two histories); it asks.
class MergeSuggestion {
  const MergeSuggestion({required this.keep, required this.merge});

  /// The one whose name and history carry on.
  final CanonicalExercise keep;

  /// The one that folds into [keep] if the user says they're the same.
  final CanonicalExercise merge;
}

/// Every pair worth asking about, most useful first.
///
/// Only exercises the user actually has — in [inUse], the canonical ids
/// referenced by their splits or history — and never one already merged
/// away, nor a pair they already said is different ([CanonicalExercise.
/// distinctFrom], checked both ways).
List<MergeSuggestion> suggestExerciseMerges(
  ExerciseLibrary library, {
  required Set<String> inUse,
}) {
  final resolver = library.resolver;
  final live = [
    for (final e in library.exercises.values)
      if (resolver.canonicalIdOf(e.id) == e.id && inUse.contains(e.id)) e,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final out = <MergeSuggestion>[];
  for (var i = 0; i < live.length; i++) {
    final a = live[i];
    final sa = ExerciseSignature.of(a.name, equipment: a.equipment);
    for (var j = i + 1; j < live.length; j++) {
      final b = live[j];
      if (a.distinctFrom.contains(b.id) || b.distinctFrom.contains(a.id)) {
        continue;
      }
      final sb = ExerciseSignature.of(b.name, equipment: b.equipment);
      if (sa.compare(sb) != SignatureMatch.plausible) continue;
      out.add(_orient(a, sa, b, sb));
    }
  }
  return out;
}

/// Which side survives a merge: the more specific one — a name that states
/// its equipment says more about the movement than one that doesn't — and
/// otherwise the older, which is the one the user has had longer.
MergeSuggestion _orient(
  CanonicalExercise a,
  ExerciseSignature sa,
  CanonicalExercise b,
  ExerciseSignature sb,
) {
  if (sa.equipment != null && sb.equipment == null) {
    return MergeSuggestion(keep: a, merge: b);
  }
  if (sb.equipment != null && sa.equipment == null) {
    return MergeSuggestion(keep: b, merge: a);
  }
  return a.createdAt.isAfter(b.createdAt)
      ? MergeSuggestion(keep: b, merge: a)
      : MergeSuggestion(keep: a, merge: b);
}

/// The alias that makes [suggestion] one exercise. Read-side only: every
/// session logged under the merged id reads as [MergeSuggestion.keep], and
/// removing the alias restores both exactly as they were.
ExerciseAlias mergeAlias(MergeSuggestion suggestion, {required DateTime now}) =>
    ExerciseAlias(
      legacyId: suggestion.merge.id,
      canonicalId: suggestion.keep.id,
      source: AliasSource.merge,
      createdAt: now,
    );

/// Both exercises, each remembering the other as different, so the pair is
/// never suggested again.
List<CanonicalExercise> markDistinct(MergeSuggestion suggestion) => [
  suggestion.keep.copyWith(
    distinctFrom: {...suggestion.keep.distinctFrom, suggestion.merge.id},
  ),
  suggestion.merge.copyWith(
    distinctFrom: {...suggestion.merge.distinctFrom, suggestion.keep.id},
  ),
];
