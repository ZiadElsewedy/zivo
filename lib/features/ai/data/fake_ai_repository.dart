import 'dart:async';

import '../domain/ai_message.dart';
import '../domain/ai_pending_action.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_role.dart';
import '../domain/ai_turn_event.dart';

/// The assistant isn't connected yet — an honest, canned reply. Never
/// masquerades as real AI (ADR-001's client-seam-first requirement).
const kFakeAiReply =
    "The assistant isn't connected yet — this is a placeholder reply. "
    "Once the gateway is deployed I'll answer using your real ZIVO data.";

const _conversationId = 'local';

/// Pure in-memory `AiRepository`: no Firestore, no network. Appends the user's
/// message then an assistant reply, broadcasting both. Understands one local
/// "add task <title>" shortcut so the ADR-003 confirmation flow can be tried
/// offline; every other message gets the honest canned reply. [proposeAction]
/// lets tests drive a proposal of any kind directly.
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
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    onEvent?.call(const AiPhaseEvent(AiPhase.understanding));

    final (userId, userCreatedAt) = _next();
    _messages.add(
      AiMessage(
        id: userId,
        role: AiRole.user,
        content: trimmed,
        createdAt: userCreatedAt,
      ),
    );

    // A single local shortcut so the propose→confirm card can be tried offline.
    const prefix = 'add task ';
    if (trimmed.toLowerCase().startsWith(prefix) &&
        trimmed.length > prefix.length) {
      final title = trimmed.substring(prefix.length).trim();
      if (title.isNotEmpty) {
        onEvent?.call(const AiPhaseEvent(AiPhase.preparingChange));
        proposeAction(
          kind: 'create_task',
          summary: 'Add task "$title"',
          fields: {'title': title, 'due': null, 'priority': 'Normal'},
        );
        onEvent?.call(const AiPhaseEvent(AiPhase.done));
        return;
      }
    }

    // Stream the canned reply in a few chunks so the live-text path is exercised
    // offline, then persist it and close the turn.
    if (onEvent != null) {
      const chunks = 3;
      final step = (kFakeAiReply.length / chunks).ceil();
      for (var i = 0; i < kFakeAiReply.length; i += step) {
        final end = (i + step).clamp(0, kFakeAiReply.length);
        onEvent(AiDeltaEvent(kFakeAiReply.substring(i, end)));
      }
    }

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
    onEvent?.call(const AiPhaseEvent(AiPhase.done));
  }

  /// Appends an assistant proposal (confirmation card). Test/offline-demo hook.
  void proposeAction({
    required String kind,
    required String summary,
    required Map<String, dynamic> fields,
  }) {
    final (id, createdAt) = _next();
    _messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        content: summary,
        createdAt: createdAt,
        pendingAction: AiPendingAction(
          actionId: id,
          kind: kind,
          summary: summary,
          fields: fields,
          status: AiActionStatus.pending,
        ),
      ),
    );
    _controller.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) async {
    final action = _resolve(actionId, AiActionStatus.applied);
    if (action == null) return;
    final (id, createdAt) = _next();
    _messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        content: _resultLine(action),
        createdAt: createdAt,
      ),
    );
    _controller.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) async {
    final action = _resolve(actionId, AiActionStatus.cancelled);
    if (action == null) return;
    final (id, createdAt) = _next();
    _messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        content: "Okay — I won't add that.",
        createdAt: createdAt,
      ),
    );
    _controller.add(List.unmodifiable(_messages));
  }

  /// Flips a still-pending action to [status] in place; returns it, or null if
  /// missing or already resolved (idempotent).
  AiPendingAction? _resolve(String actionId, AiActionStatus status) {
    final i = _messages.indexWhere(
      (m) => m.pendingAction?.actionId == actionId,
    );
    if (i == -1) return null;
    final action = _messages[i].pendingAction!;
    if (!action.isPending) return null;
    _messages[i] = _messages[i].copyWith(
      pendingAction: action.copyWith(status: status),
    );
    return action;
  }

  String _resultLine(AiPendingAction a) {
    switch (a.kind) {
      case 'create_task':
        return 'Added to Tasks · ${a.fields['title']}';
      case 'create_expense':
        return 'Logged expense · ${a.fields['amount']} ${a.fields['currency']}';
      case 'create_event':
        return 'Added to Schedule · ${a.fields['title']}';
      default:
        return 'Done.';
    }
  }

  void dispose() => _controller.close();
}
