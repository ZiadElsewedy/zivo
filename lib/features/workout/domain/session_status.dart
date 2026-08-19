/// The lifecycle of a [LiveSession].
///
/// - [active]    — in progress (being performed / edited).
/// - [completed] — finished and logged to history.
/// - [abandoned] — quit before finishing (discarded, not logged).
enum SessionStatus { active, completed, abandoned }

/// Parses a stored [SessionStatus] name, defaulting to [SessionStatus.active].
SessionStatus sessionStatusFromName(String? name) =>
    SessionStatus.values.firstWhere((s) => s.name == name, orElse: () => SessionStatus.active);
