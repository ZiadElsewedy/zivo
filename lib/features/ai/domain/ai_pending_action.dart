/// The lifecycle of a proposed change (ADR-003).
enum AiActionStatus { pending, applied, cancelled, expired }

AiActionStatus aiActionStatusFromName(String? name) => AiActionStatus.values
    .firstWhere((s) => s.name == name, orElse: () => AiActionStatus.pending);

/// A change the assistant wants to make but has NOT made — rendered as a
/// confirmation card in the chat. Nothing is written until the user confirms
/// (ADR-003: propose → confirm → execute). Carried on an [AiMessage].
class AiPendingAction {
  const AiPendingAction({
    required this.actionId,
    required this.kind,
    required this.summary,
    required this.fields,
    required this.status,
  });

  /// The server pending-action id; the key used to confirm or cancel.
  final String actionId;

  /// The server pending-action kind — 'create_expense' or 'mark_meal_eaten'
  /// today; the assistant's proposable changes grow here.
  final String kind;

  /// A human one-line description (fallback text).
  final String summary;

  /// Structured fields the card renders (title, amount, category, due, …).
  final Map<String, dynamic> fields;

  final AiActionStatus status;

  bool get isPending => status == AiActionStatus.pending;

  AiPendingAction copyWith({AiActionStatus? status}) => AiPendingAction(
    actionId: actionId,
    kind: kind,
    summary: summary,
    fields: fields,
    status: status ?? this.status,
  );
}
