import 'diet_import_result.dart';

/// The result of an AI PDF import attempt (Chunk B+C) — either a genuine
/// extraction, or an honest, explained decline. Declining is a normal,
/// expected outcome (the server never hallucinates a plan just to have
/// something to return), never surfaced as a thrown error — see
/// `functions/ai/diet_import.js`'s `reject_import` tool.
sealed class DietImportOutcome {
  const DietImportOutcome();
}

/// The document was read as a genuine, usable diet plan.
class DietImportAccepted extends DietImportOutcome {
  const DietImportAccepted(this.plan);

  final DietImportResult plan;
}

/// The document wasn't a diet plan, was empty/unreadable, didn't contain
/// enough usable data, or was too unclear to map reliably — [reason] is a
/// specific, plain-English explanation meant to be shown to the user
/// verbatim, not a generic error string.
class DietImportRejected extends DietImportOutcome {
  const DietImportRejected(this.reason);

  final String reason;
}
