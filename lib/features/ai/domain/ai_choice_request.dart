/// A question the assistant asked the user to answer by tapping an option,
/// rather than guessing — rendered as option chips in the chat (Ask
/// elicitation, Phase 1). Carried on an [AiMessage] the same way a proposal is.
///
/// Unlike a proposal there is no confirm/cancel and nothing pending
/// server-side: the user's pick is sent back as an ordinary next message
/// (through the normal chat send), which is what lets the coach continue. The
/// server-stored [answered] flag is not written in Phase 1 — a card stays
/// tappable on reopen, and re-answering simply sends another turn.
class AiChoiceRequest {
  const AiChoiceRequest({
    required this.requestId,
    required this.prompt,
    required this.options,
    this.allowMultiple = false,
  });

  /// The server request id for this question (stable across reloads).
  final String requestId;

  /// The question text (also the message's fallback content).
  final String prompt;

  /// The choices, in the order the model gave them.
  final List<AiChoiceOption> options;

  /// True when the user may pick more than one option. Phase 1 renders single
  /// pick; this is carried so the widget can honour it once multi-pick lands.
  final bool allowMultiple;
}

/// One tappable option: [value] is a stable key, [label] is what the user sees
/// (and what gets sent back as their answer).
class AiChoiceOption {
  const AiChoiceOption({required this.value, required this.label});

  final String value;
  final String label;
}
