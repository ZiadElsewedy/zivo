import 'dart:typed_data';

import '../../diet/domain/diet_import_input.dart';
import '../../diet/domain/diet_import_outcome.dart';
import '../../workout/domain/workout_import_outcome.dart';
import 'ai_conversation.dart';
import 'ai_message.dart';
import 'ai_response_style.dart';
import 'ai_turn_event.dart';
import 'stt_outcome.dart';

/// The seam between the app and the AI assistant ("Ask"). Storage-agnostic
/// so both today's in-memory [FakeAiRepository] and the future
/// `FirebaseAiRepository` (Firestore reads + the `aiChat` callable) fit.
abstract interface class AiRepository {
  /// Ensures there is an active conversation and returns its id (creating one
  /// on first use). Kept for the app's initial/default conversation; callers
  /// that manage multiple sessions also use [createConversation].
  Future<String> ensureConversation();

  /// The user's conversations, newest-`updatedAt` first, as a live stream.
  Stream<List<AiConversation>> watchConversations();

  /// A one-shot read of the single most-recently-updated conversation, or
  /// null if the user has none. Used to resume the last conversation on
  /// launch (and to pick a new active one after deleting the current) —
  /// deliberately NOT `watchConversations().first`, whose first emission can
  /// be a stale/empty local-cache snapshot that resolves before Firestore's
  /// server data arrives (the resume-most-recent bug this method fixes).
  Future<AiConversation?> latestConversation();

  /// Creates a new, empty conversation and returns its id. [title] names the
  /// chat up front (e.g. "Workout Changes") when the user named it at
  /// creation; it defaults to 'New chat', which the first message's
  /// auto-title then replaces.
  Future<String> createConversation({String? title});

  /// Renames [id]'s conversation to [title] — used for the auto-title applied
  /// after the first user message in a still-untitled ('New chat') session.
  Future<void> renameConversation(String id, String title);

  /// Permanently deletes [id]'s conversation and every message under it, via
  /// the `aiDeleteConversation` callable (Admin SDK `recursiveDelete` —
  /// clients can't delete a conversation directly, since Firestore rules
  /// forbid removing the server-written `messages` subcollection).
  Future<void> deleteConversation(String id);

  /// The user's saved reply-length preference (one of [kResponseStyles]),
  /// persisted at `users/{uid}/settings/ai`. Defaults to
  /// [kDefaultResponseStyle] when never set.
  Future<String> getResponseStyle();

  /// Persists the user's reply-length preference.
  Future<void> setResponseStyle(String style);

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
  ///
  /// [responseStyle] is the caller's current [getResponseStyle] value
  /// (defaulting to [kDefaultResponseStyle]) — forwarded to the gateway so it
  /// can adjust reply length/depth.
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,

    /// Client-generated idempotency key for THIS turn (stable across retries
    /// of the same logical message). The server uses it to skip appending a
    /// duplicate user message and to replay an already-written assistant
    /// reply instead of generating a second one when a retry races a slow
    /// first attempt that actually succeeded server-side.
    String? clientTurnId,
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

  /// Extracts a proposed workout split from a document's raw bytes
  /// (WORKOUT_SYSTEM.md §3.4, Phase 6) via the `aiImportWorkoutPlan`
  /// callable — one Claude call, no Firestore write. The caller reviews/edits
  /// the result before saving it (via `WorkoutPlanRepository.saveSplit`);
  /// this method alone never creates a split.
  ///
  /// [mimeType] is the picked file's media type: `application/pdf`, or an
  /// image type (`image/jpeg`, `image/png`, …) when the user imported a
  /// photo of their plan instead of a PDF.
  ///
  /// Resolves to [WorkoutImportRejected] (never throws) when the document
  /// genuinely isn't/doesn't contain a usable plan — throwing stays reserved
  /// for real technical failures (network, auth/App Check, server error).
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List fileBytes,
    required String mimeType,
  });

  /// Extracts a proposed diet plan from [input] via the `aiImportDietPlan`
  /// callable — one Claude call, no Firestore write. The caller reviews/edits
  /// the result before saving it (via `DietRepository.savePlan`); this method
  /// alone never creates a plan.
  ///
  /// [input] is either a document (a PDF or a photo) or the user's own
  /// description of their plan — dictated and transcribed by [transcribe]
  /// first, or typed. **One extractor and one schema serve all four capture
  /// routes**; four prompts producing four shapes is how they drift apart.
  ///
  /// Resolves to [DietImportRejected] (never throws) when the material
  /// genuinely isn't/doesn't contain a usable plan — throwing stays reserved
  /// for real technical failures (network, auth/App Check, server error).
  Future<DietImportOutcome> importDietPlan(DietImportInput input);

  /// Transcribes a recorded voice note via the `aiTranscribe` callable
  /// (`functions/ai/speech/gateway.js`) — input only: this never calls the
  /// LLM and never speaks text back. The caller (the composer's mic button)
  /// places the returned text in the input field for the user to edit/send
  /// via [send]; nothing here sends anything itself.
  ///
  /// [languageHint] should be omitted by default so code-switched Arabic/
  /// English speech transcribes verbatim rather than being forced into one
  /// language — only pass it when the caller genuinely knows the language.
  ///
  /// Resolves to [SttFailed] (never throws) for any failure, technical or
  /// otherwise — the caller always has an outcome to switch on.
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  });
}
