import 'dart:async';

import '../domain/ai_message.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_role.dart';

/// The assistant isn't connected yet — an honest, canned reply. Never
/// masquerades as real AI (ADR-001's client-seam-first requirement).
const kFakeAiReply =
    "The assistant isn't connected yet — this is a placeholder reply. "
    "Once the gateway is deployed I'll answer using your real ZIVO data.";

const _conversationId = 'local';

/// Pure in-memory `AiRepository`: no Firestore, no network. Appends the
/// user's message then the honest canned reply, broadcasting both.
class FakeAiRepository implements AiRepository {
  final List<AiMessage> _messages = [];
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();
  int _sequence = 0;

  /// A strictly increasing (id, createdAt) pair, even across calls made in
  /// the same microsecond.
  (String, DateTime) _next() {
    final now = DateTime.now().add(Duration(microseconds: _sequence));
    _sequence++;
    return (now.microsecondsSinceEpoch.toString(), now);
  }

  @override
  Future<String> ensureConversation() async => _conversationId;

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) async* {
    yield List.unmodifiable(_messages);
    yield* _controller.stream;
  }

  @override
  Future<void> send({required String conversationId, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final (userId, userCreatedAt) = _next();
    _messages.add(
      AiMessage(id: userId, role: AiRole.user, content: trimmed, createdAt: userCreatedAt),
    );
    final (assistantId, assistantCreatedAt) = _next();
    _messages.add(
      AiMessage(
        id: assistantId,
        role: AiRole.assistant,
        content: kFakeAiReply,
        createdAt: assistantCreatedAt,
      ),
    );
    _controller.add(List.unmodifiable(_messages));
  }

  void dispose() => _controller.close();
}
