/// The lifecycle of a [LiveSession].
///
/// - [active]    — in progress (being performed / edited).
/// - [completed] — finished and logged to history.
/// - [abandoned] — quit before finishing (discarded, not logged).
/// - [voided]    — a real, finished session withdrawn from the statistics
///                 with a reason, its record kept intact.
///
/// **[voided] is why deleting a completed session is no longer offered.** A
/// tracker whose history can be edited to taste is a tracker whose numbers
/// mean nothing, so a session that actually happened is never erased — it is
/// marked, with [LiveSession.voidReason] saying why, and every average, streak
/// and analysis skips it while History still shows it struck through. The one
/// thing still hard-deleted is a session with nothing logged in it at all,
/// which is indistinguishable from never having started one.
enum SessionStatus { active, completed, abandoned, voided }

/// Parses a stored [SessionStatus] name, defaulting to [SessionStatus.active].
SessionStatus sessionStatusFromName(String? name) =>
    SessionStatus.values.firstWhere((s) => s.name == name, orElse: () => SessionStatus.active);

/// Why a finished session was withdrawn from the statistics. Stored by `name`,
/// so these are ids — their user-facing labels live in
/// `presentation/workout_labels.dart` like every other persisted enum.
enum VoidReason {
  /// The clock ran on after training stopped (the classic "left it open
  /// overnight"), and the duration can't be recovered.
  badDuration,

  /// Logged against the wrong day, or started by accident.
  loggedByMistake,

  /// Someone else used the phone / a test entry.
  notMine,

  other,
}

/// Parses a stored [VoidReason] name, defaulting to [VoidReason.other] so an
/// unknown value never costs the void itself.
VoidReason voidReasonFromName(String? name) =>
    VoidReason.values.firstWhere((r) => r.name == name, orElse: () => VoidReason.other);
