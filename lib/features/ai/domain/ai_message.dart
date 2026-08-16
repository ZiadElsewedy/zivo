import 'ai_pending_action.dart';
import 'ai_role.dart';

/// One turn in an [AiConversation] — the user's text, the assistant's reply,
/// or (ADR-003) an assistant proposal carrying a [pendingAction] the user can
/// confirm or cancel.
class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.pendingAction,
  });

  final String id;
  final AiRole role;
  final String content;
  final DateTime createdAt;

  /// Non-null when this message is a confirmation-card proposal.
  final AiPendingAction? pendingAction;

  AiMessage copyWith({AiPendingAction? pendingAction}) => AiMessage(
    id: id,
    role: role,
    content: content,
    createdAt: createdAt,
    pendingAction: pendingAction ?? this.pendingAction,
  );
}
