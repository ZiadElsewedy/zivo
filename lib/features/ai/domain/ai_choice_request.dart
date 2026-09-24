/// A question the assistant asked the user to answer by tapping an option,
/// rather than guessing — rendered as tappable option cards in the chat (Ask
/// elicitation). Carried on an [AiMessage] the same way a proposal is.
///
/// Unlike a proposal there is no confirm/cancel: the user's tap is sent back
/// as the next turn carrying an [AiChoiceSelection] — the option's stable
/// [AiChoiceOption.value], resolved server-side against the stored card
/// (`functions/ai/chat/choices.js`), never re-parsed from text. Once answered
/// the server records [selectedValue], so the card renders settled on reload
/// and on every device, and can't be answered twice.
class AiChoiceRequest {
  const AiChoiceRequest({
    required this.requestId,
    required this.prompt,
    required this.options,
    this.allowMultiple = false,
    this.selectedValue,
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

  /// The value of the option the user picked, as the server recorded it —
  /// null while the question is still open.
  final String? selectedValue;
}

/// The user's answer to an [AiChoiceRequest]: which card, and which option by
/// its stable id. This — not the label shown in the bubble — is what the
/// server acts on.
class AiChoiceSelection {
  const AiChoiceSelection({required this.requestId, required this.value});

  final String requestId;
  final String value;
}

/// One tappable option: [value] is its stable id, [label] is what the user
/// sees (and what shows as their message once picked). [subtitle] is an
/// optional second line of detail — e.g. a "247 kcal / 100g" figure on a
/// search_food_product candidate — so options that would otherwise look
/// identical stay distinguishable.
///
/// [metadata] holds the server-verified figures behind an option (a priced
/// food swap's `grams` / `kcal` / `proteinG` …). When they're there, the card
/// renders them in the reader's language instead of the server's English
/// [subtitle] — they are never figures the model wrote.
class AiChoiceOption {
  const AiChoiceOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.metadata = const {},
  });

  final String value;
  final String label;
  final String? subtitle;
  final Map<String, num> metadata;
}
