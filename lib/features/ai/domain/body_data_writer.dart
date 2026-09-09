/// The seam the Ask input form (Phase 3) writes the user's own body data
/// through, so a value the coach asked for once is remembered and never asked
/// again. Kept as an interface here — with none of diet/workout wired in — so
/// the controller can be unit-tested with a fake, and so the app decides which
/// repositories back it.
///
/// Deliberately narrow. Only the two values that (a) the coach commonly lacks
/// and (b) have a direct, user-owned write path are here: current weight (a
/// weigh-in) and height (the body profile). **Targets/goal are NOT writable
/// through this** — the app's rule stands that a target exists only once the
/// user has approved one (see `diet/domain/body_profile.dart`), and the coach
/// must never set one from a form.
abstract interface class BodyDataWriter {
  /// Records a weigh-in of [weightKg]. A value outside a believable range is
  /// ignored (a typo guard, not a judgement).
  Future<void> saveWeightKg(double weightKg);

  /// Merges [heightCm] into the user's body profile, returning true when it was
  /// saved. Returns false when there is no profile to merge into (height alone
  /// can't build a valid one — sex and activity are required) or the value is
  /// implausible; the caller treats a false as "not remembered" and lets the
  /// value flow on to the coach as ordinary context.
  Future<bool> saveHeightCm(double heightCm);
}

/// The canonical `request_input` field keys the form persists. The model must
/// use these exact keys (documented in the tool) for a value to be remembered;
/// any other key is conversation-only.
const String kBodyInputHeightCm = 'heightCm';
const String kBodyInputWeightKg = 'weightKg';
