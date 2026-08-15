import 'ai_role.dart';

/// One turn in an [AiConversation] — either the user's text or the
/// assistant's (or, later, a server tool transcript) reply.
class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final AiRole role;
  final String content;
  final DateTime createdAt;
}
