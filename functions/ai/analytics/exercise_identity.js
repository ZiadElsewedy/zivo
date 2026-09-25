/**
 * Exercise identity for the coach — the Node mirror of the Dart
 * `ExerciseIdentityResolver` (ADR-017).
 *
 * Every progression engine here keys on `SessionExercise.exerciseId`. Before
 * identities existed that was a plan SLOT id, so the same movement on two days
 * (or in two splits) had two unrelated histories. The fix lives in data, not
 * in the engines: legacy ids fold into their canonical exercise through the
 * `users/{uid}/exerciseAliases` layer, applied when history is READ. Sessions
 * are never rewritten, which is what keeps every alias reversible — and the
 * engines stay exactly as pinned by their golden vectors.
 *
 * Pass sessions through `canonicalize` before any per-exercise analysis,
 * exactly as the app does, or the coach and the Analysis screen will disagree
 * about what one lift's history is.
 */

/**
 * @param {!Array<{legacyId: string, canonicalId: string}>} aliases
 * @return {{canonicalIdOf: function(string): string,
 *           canonicalize: function(!Array<Object>): !Array<Object>,
 *           isEmpty: boolean}}
 */
function makeResolver(aliases) {
  const map = new Map();
  for (const a of aliases || []) {
    if (a && a.legacyId && a.canonicalId) map.set(a.legacyId, a.canonicalId);
  }

  // Follows chains (a → b after b was merged into c resolves to c) and stops
  // on a cycle, returning the last id reached — a corrupt mapping degrades to
  // "not merged", never to a hang. Same contract as the Dart resolver.
  const canonicalIdOf = (id) => {
    let current = id;
    const seen = new Set([current]);
    for (;;) {
      const next = map.get(current);
      if (next == null || seen.has(next)) return current;
      seen.add(next);
      current = next;
    }
  };

  const canonicalize = (sessions) => {
    if (map.size === 0) return sessions;
    return (sessions || []).map((s) => {
      const touches = (s.exercises || []).some((e) => map.has(e.exerciseId));
      if (!touches) return s;
      return {
        ...s,
        exercises: s.exercises.map((e) => map.has(e.exerciseId) ?
          {...e, exerciseId: canonicalIdOf(e.exerciseId)} :
          e),
      };
    });
  };

  return {canonicalIdOf, canonicalize, isEmpty: map.size === 0};
}

/** Resolves nothing — every id means itself. */
const IDENTITY = makeResolver([]);

module.exports = {makeResolver, IDENTITY};
