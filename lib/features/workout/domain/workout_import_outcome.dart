import 'workout_import_result.dart';

/// The result of an AI PDF import attempt (WORKOUT_SYSTEM.md §3.4) — either
/// a genuine extraction, or an honest, explained decline. Declining is a
/// normal, expected outcome (the server never hallucinates a plan just to
/// have something to return), never surfaced as a thrown error — see
/// `functions/ai/workout_import.js`'s `reject_import` tool.
sealed class WorkoutImportOutcome {
  const WorkoutImportOutcome();
}

/// The document was read as a genuine, usable workout plan.
class WorkoutImportAccepted extends WorkoutImportOutcome {
  const WorkoutImportAccepted(this.plan);

  final WorkoutImportResult plan;
}

/// The document wasn't a workout plan, was empty/unreadable, didn't contain
/// enough usable data, or was too unclear to map reliably — [reason] is a
/// specific, plain-English explanation meant to be shown to the user
/// verbatim, not a generic error string.
class WorkoutImportRejected extends WorkoutImportOutcome {
  const WorkoutImportRejected(this.reason);

  final String reason;
}
