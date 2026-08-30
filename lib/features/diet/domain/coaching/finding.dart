/// What kind of thing the coach is saying.
///
/// Requirement 9 of the original brief, made structural: a coach that cannot
/// tell an observation from a recommendation ends up delivering both in the
/// same flat voice, and a warning gets lost among encouragements. Typing them
/// means the engine decides which register it is in, and the model only has to
/// phrase it.
enum FindingKind {
  /// A fact from the state. "You've logged 1,850 kcal."
  observation,

  /// What that fact means against the objective. "That's 350 under target."
  analysis,

  /// Something to do about it. Always carries the reason with it.
  recommendation,

  /// Something that could do harm if ignored.
  warning,

  /// A real win, stated because it happened — never as filler.
  encouragement,

  /// A question, or a statement of what the app doesn't know. The honest
  /// answer when the state is too thin to coach from.
  clarification,
}

/// What the register is called where the user can see it.
///
/// The kind is already decided in code; naming it on screen is what stops six
/// sentences reading as one flat stream — a warning that looks exactly like an
/// observation has lost the distinction the type was created to make.
String findingKindLabel(FindingKind kind) => switch (kind) {
  FindingKind.observation => 'Observation',
  FindingKind.analysis => 'Analysis',
  FindingKind.recommendation => 'Suggestion',
  FindingKind.warning => 'Warning',
  FindingKind.encouragement => 'Going well',
  FindingKind.clarification => 'Worth knowing',
};

/// How much this finding should outrank the others when the set is capped.
enum FindingSeverity { info, notable, important, urgent }

/// One thing the coach could truthfully say, decided in code.
///
/// **The engine decides; the model phrases.** Every finding carries a
/// deterministic [text] that is correct on its own, so a rejected or
/// unavailable model reply can always fall back to it (the Phase 7 validator
/// depends on exactly this), and an [evidence] list naming the state fields it
/// was derived from — which is what makes "why is this being said?" answerable
/// rather than asserted.
class CoachingFinding {
  const CoachingFinding({
    required this.code,
    required this.kind,
    required this.severity,
    required this.text,
    required this.evidence,
  });

  /// Stable machine name, e.g. `protein_shortfall`. Referenced by tests and
  /// by the validator; do not rename casually.
  final String code;

  final FindingKind kind;
  final FindingSeverity severity;

  /// A plain, correct sentence. Not the final wording the user sees — the
  /// coach rephrases it — but always true, and always usable as-is.
  final String text;

  /// The `DietState` paths this was derived from, e.g.
  /// `['remaining.proteinG', 'targets.proteinG']`. A finding that can't say
  /// what it rests on has no business being shown.
  final List<String> evidence;
}
