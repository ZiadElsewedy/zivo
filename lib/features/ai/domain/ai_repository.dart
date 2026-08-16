import 'ai_message.dart';
import 'ai_turn_event.dart';

/// The seam between the app and the AI assistant ("Ask"). Storage-agnostic
/// so both today's in-memory [FakeAiRepository] and the future
/// `FirebaseAiRepository` (Firestore reads + the `aiChat` callable) fit.
abstract interface class AiRepository {
  /// Ensures there is an active conversation and returns its id (creating one
  /// on first use). V1 keeps a single active conversation.
  Future<String> ensureConversation();

  /// The messages in [conversationId], oldest first, as a live stream.
  Stream<List<AiMessage>> watchMessages(String conversationId);

  /// Sends the user's [text] for [conversationId]. In the real impl this calls
  /// the `aiChat` gateway, which persists the user message and the assistant
  /// reply; the new messages surface via [watchMessages]. In the fake it
  /// appends the user message and a canned assistant reply in memory.
  ///
  /// When [onEvent] is supplied, the turn is streamed: [AiPhaseEvent] and
  /// [AiDeltaEvent] values arrive live as the gateway progresses. Implementations
  /// that can't stream simply never call it — the reply still surfaces via
  /// [watchMessages], and the caller falls back to a buffered reveal. The
  /// returned future completes when the turn's durable record is written.
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  });

  /// Confirms a proposed action (ADR-003), executing its write server-side via
  /// the `aiConfirmAction` callable. Idempotent — a double-confirm is a no-op.
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  });

  /// Cancels a proposed action (`aiCancelAction`); nothing is written.
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  });
}
