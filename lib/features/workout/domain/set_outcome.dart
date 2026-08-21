/// What became of one prescribed set: never touched yet ([pending]),
/// actually performed ([completed]), or deliberately passed over
/// ([skipped]). Distinct from a boolean `done` flag so a skip can never be
/// mistaken for a completed set — a skipped set carries no logged volume,
/// but still occupies its place in the exercise so the review screen can
/// offer it back.
enum SetOutcome { pending, completed, skipped }

/// Parses a stored [SetOutcome] name, falling back to `pending` for any
/// unknown or legacy value — including a pre-outcome doc's missing field
/// (migrated separately from the old `done` bool; see
/// `FirestoreWorkoutSessionRepository._setFromMap`).
SetOutcome setOutcomeFromName(String? name) =>
    SetOutcome.values.firstWhere((o) => o.name == name, orElse: () => SetOutcome.pending);
