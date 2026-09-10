import 'ai_choice_request.dart';

/// A small form the assistant asked the user to fill in (Ask elicitation
/// Phase 2) when it needs a specific value no tool can supply — a height, a
/// target weight. Rendered as an input card in the chat and carried on an
/// [AiMessage].
///
/// Like a choice question and unlike a write proposal, there is no confirm and
/// nothing pending server-side: the user's entries are serialized and sent back
/// as an ordinary next message (see `AskController.submitInput`), which is what
/// lets the coach continue. Phase 2 does NOT persist the values to the user's
/// profile — that is Phase 3.
class AiInputRequest {
  const AiInputRequest({
    required this.requestId,
    required this.prompt,
    required this.fields,
  });

  /// The server request id for this form (stable across reloads).
  final String requestId;

  /// The one-line ask ("Give me a couple of details first"). Also the
  /// message's fallback content.
  final String prompt;

  /// The fields to collect, in the order the model gave them.
  final List<AiInputField> fields;
}

/// The kind of a single [AiInputField] — a numeric entry, free text, or a pick
/// from [AiInputField.options]. An unrecognized server value maps to [text].
enum AiInputFieldType {
  number,
  text,
  choice;

  static AiInputFieldType fromName(String? name) => AiInputFieldType.values
      .firstWhere((t) => t.name == name, orElse: () => AiInputFieldType.text);
}

/// One field in an [AiInputRequest].
class AiInputField {
  const AiInputField({
    required this.key,
    required this.label,
    required this.type,
    this.unit,
    this.options = const [],
    this.required = true,
  });

  /// A short stable id (e.g. `heightCm`) — used as the field's key in the
  /// answer the coach reads back.
  final String key;

  /// What the user sees above the field.
  final String label;

  final AiInputFieldType type;

  /// A unit suffix for a [AiInputFieldType.number] field (`cm`, `kg`), or null.
  final String? unit;

  /// The choices for a [AiInputFieldType.choice] field; empty otherwise.
  final List<AiChoiceOption> options;

  /// Whether the user must fill this field before the form can be submitted.
  final bool required;
}
