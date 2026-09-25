import '../live_session.dart';
import 'exercise_alias.dart';

/// Reads history through the identity model: turns whatever id a record was
/// written with into the canonical exercise it means today.
///
/// Every progression engine (`workout_analytics`, `exercise_analysis`,
/// `lastPerformanceFor`, PR detection) keys on `SessionExercise.exerciseId`
/// and knows nothing about identities. Rather than teach each of them, the
/// sessions are passed through [canonicalize] first — so the engines stay
/// exactly as pinned by their golden vectors, and "same exercise" becomes a
/// property of the data they are given.
///
/// **In memory only.** The canonicalized sessions are a *reading* of the
/// record, not a new version of it: never save one back. A session keeps the
/// id it was logged with, which is what makes every alias reversible.
class ExerciseIdentityResolver {
  ExerciseIdentityResolver(Iterable<ExerciseAlias> aliases)
    : _aliases = {for (final a in aliases) a.legacyId: a.canonicalId};

  /// Resolves nothing — every id means itself. The state of an account with
  /// no aliases, i.e. of every account before identities existed.
  static final identity = ExerciseIdentityResolver(const []);

  final Map<String, String> _aliases;

  bool get isEmpty => _aliases.isEmpty;

  /// The canonical id [id] means. Follows chains (a → b after b was itself
  /// merged into c resolves to c) and stops on a cycle rather than looping,
  /// returning the last id reached before it repeated — a corrupt mapping
  /// degrades to "not merged", never to a hang.
  String canonicalIdOf(String id) {
    var current = id;
    final seen = <String>{current};
    while (true) {
      final next = _aliases[current];
      if (next == null || !seen.add(next)) return current;
      current = next;
    }
  }

  /// Whether [a] and [b] are the same exercise.
  bool same(String a, String b) => canonicalIdOf(a) == canonicalIdOf(b);

  /// [sessions] with every exercise's `exerciseId` resolved to its canonical
  /// id. Returns [sessions] itself when there is nothing to resolve, so the
  /// common case allocates nothing.
  List<LiveSession> canonicalize(List<LiveSession> sessions) {
    if (_aliases.isEmpty) return sessions;
    return [
      for (final s in sessions)
        s.exercises.any((e) => _aliases.containsKey(e.exerciseId))
            ? s.copyWith(
                exercises: [
                  for (final e in s.exercises)
                    _aliases.containsKey(e.exerciseId)
                        ? e.copyWith(exerciseId: canonicalIdOf(e.exerciseId))
                        : e,
                ],
              )
            : s,
    ];
  }
}
