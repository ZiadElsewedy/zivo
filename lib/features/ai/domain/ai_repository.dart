import 'ai_message.dart';

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
  Future<void> send({required String conversationId, required String text});
}
