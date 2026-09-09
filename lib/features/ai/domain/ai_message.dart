import 'ai_choice_request.dart';
import 'ai_pending_action.dart';
import 'ai_role.dart';

/// One turn in an [AiConversation] — the user's text, the assistant's reply,
/// an (ADR-003) assistant proposal carrying a [pendingAction] the user can
/// confirm or cancel, or an assistant [choiceRequest] (Ask elicitation) the
/// user answers by tapping an option.
class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.pendingAction,
    this.choiceRequest,
    this.clientTurnId,
  });

  final String id;
  final AiRole role;
  final String content;
  final DateTime createdAt;

  /// Non-null when this message is a confirmation-card proposal.
  final AiPendingAction? pendingAction;

  /// Non-null when this message is an assistant question with option chips.
  final AiChoiceRequest? choiceRequest;

  /// The client-generated idempotency key of the turn that produced this
  /// message, when it belongs to one (`aiChat`'s `clientTurnId`). Both sides
  /// of a turn — the persisted user message and the assistant's reply — carry
  /// the SAME value, which is how the UI pairs an optimistic bubble with the
  /// durable copies of exactly that turn (no counts, no text compares).
  /// Null on legacy messages written before turn dedup existed and on
  /// turn-less writes (confirm/cancel result lines).
  final String? clientTurnId;

  AiMessage copyWith({
    AiPendingAction? pendingAction,
    AiChoiceRequest? choiceRequest,
  }) => AiMessage(
    id: id,
    role: role,
    content: content,
    createdAt: createdAt,
    pendingAction: pendingAction ?? this.pendingAction,
    choiceRequest: choiceRequest ?? this.choiceRequest,
    clientTurnId: clientTurnId,
  );
}
