import 'dart:async';
import 'dart:typed_data';

import '../../workout/domain/workout_import_outcome.dart';
import '../../workout/domain/workout_import_result.dart';
import '../domain/ai_conversation.dart';
import '../domain/ai_message.dart';
import '../domain/ai_pending_action.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_response_style.dart';
import '../domain/ai_role.dart';
import '../domain/ai_turn_event.dart';
import '../domain/stt_outcome.dart';

/// The assistant isn't connected yet — an honest, canned reply. Never
/// masquerades as real AI (ADR-001's client-seam-first requirement).
const kFakeAiReply =
    "The assistant isn't connected yet — this is a placeholder reply. "
    "Once the gateway is deployed I'll answer using your real ZIVO data.";

/// One in-memory conversation: its messages plus a broadcast stream of them.
class _FakeConversation {
  _FakeConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  final List<AiMessage> messages = [];
  final StreamController<List<AiMessage>> controller =
      StreamController<List<AiMessage>>.broadcast();
}

/// Pure in-memory `AiRepository`: no Firestore, no network. Appends the user's
/// message then an assistant reply, broadcasting both. Understands one local
/// "add task <title>" shortcut so the ADR-003 confirmation flow can be tried
/// offline; every other message gets the honest canned reply. [proposeAction]
/// lets tests drive a proposal of any kind directly. Keeps an in-memory list
/// of conversations, each with its own message list, so multi-session UI
/// (new chat / switch / sessions list) is testable without a backend.
class FakeAiRepository implements AiRepository {
  FakeAiRepository({
    Future<WorkoutImportOutcome> Function(Uint8List pdfBytes)?
    importWorkoutPlanImpl,
    Future<SttOutcome> Function(
      Uint8List audioBytes,
      String mimeType,
      String? languageHint,
    )?
    transcribeImpl,
  }) : _importWorkoutPlanImpl =
           importWorkoutPlanImpl ?? _defaultImportWorkoutPlan,
       _transcribeImpl = transcribeImpl ?? _defaultTranscribe;

  final Future<WorkoutImportOutcome> Function(Uint8List pdfBytes)
  _importWorkoutPlanImpl;
  final Future<SttOutcome> Function(
    Uint8List audioBytes,
    String mimeType,
    String? languageHint,
  )
  _transcribeImpl;

  final Map<String, _FakeConversation> _conversations = {};
  final StreamController<List<AiConversation>> _conversationsController =
      StreamController<List<AiConversation>>.broadcast();

  /// The conversation [ensureConversation] returns — created lazily on first
  /// call, then reused, mirroring the real repo's single-cached-id behavior.
  String? _defaultConversationId;

  String _responseStyle = kDefaultResponseStyle;

  int _sequence = 0;
  int _conversationSequence = 0;

  /// A strictly increasing (id, createdAt) pair, even across calls made in
  /// the same microsecond.
  (String, DateTime) _next() {
    final now = DateTime.now().add(Duration(microseconds: _sequence));
    _sequence++;
    return (now.microsecondsSinceEpoch.toString(), now);
  }

  _FakeConversation _createConversation({required String title}) {
    final now = DateTime.now().add(
      Duration(microseconds: _sequence + _conversationSequence),
    );
    final id = 'conv-${_conversationSequence++}';
    final convo = _FakeConversation(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _conversations[id] = convo;
    _emitConversations();
    return convo;
  }

  void _emitConversations() {
    final list = _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _conversationsController.add([
      for (final c in list)
        AiConversation(
          id: c.id,
          title: c.title,
          createdAt: c.createdAt,
          updatedAt: c.updatedAt,
        ),
    ]);
  }

  @override
  Future<String> ensureConversation() async {
    final existing = _defaultConversationId;
    if (existing != null && _conversations.containsKey(existing)) {
      return existing;
    }
    final convo = _createConversation(title: 'Ask');
    _defaultConversationId = convo.id;
    return convo.id;
  }

  @override
  Future<String> createConversation() async =>
      _createConversation(title: 'New chat').id;

  @override
  Future<void> renameConversation(String id, String title) async {
    final convo = _conversations[id];
    if (convo == null) return;
    convo.title = title;
    _emitConversations();
  }

  @override
  Future<void> deleteConversation(String id) async {
    final convo = _conversations.remove(id);
    if (convo == null) return;
    convo.controller.close();
    if (_defaultConversationId == id) _defaultConversationId = null;
    _emitConversations();
  }

  @override
  Future<String> getResponseStyle() async => _responseStyle;

  @override
  Future<void> setResponseStyle(String style) async =>
      _responseStyle = validResponseStyle(style);

  @override
  Stream<List<AiConversation>> watchConversations() async* {
    final list = _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield [
      for (final c in list)
        AiConversation(
          id: c.id,
          title: c.title,
          createdAt: c.createdAt,
          updatedAt: c.updatedAt,
        ),
    ];
    yield* _conversationsController.stream;
  }

  @override
  Future<AiConversation?> latestConversation() async {
    if (_conversations.isEmpty) return null;
    final c = _conversations.values.reduce(
      (a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a,
    );
    return AiConversation(
      id: c.id,
      title: c.title,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    );
  }

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) async* {
    final convo = _conversations[conversationId];
    if (convo == null) {
      yield const [];
      return;
    }
    yield List.unmodifiable(convo.messages);
    yield* convo.controller.stream;
  }

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final convo = _conversations[conversationId];
    if (convo == null) return;

    onEvent?.call(const AiPhaseEvent(AiPhase.understanding));

    final (userId, userCreatedAt) = _next();
    convo.messages.add(
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
          conversationId: conversationId,
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
    convo.messages.add(
      AiMessage(
        id: assistantId,
        role: AiRole.assistant,
        content: kFakeAiReply,
        createdAt: assistantCreatedAt,
      ),
    );
    convo.updatedAt = assistantCreatedAt;
    _emitConversations();
    convo.controller.add(List.unmodifiable(convo.messages));
    onEvent?.call(const AiPhaseEvent(AiPhase.done));
  }

  /// Appends an assistant proposal (confirmation card) to [conversationId]
  /// (defaulting to the conversation [ensureConversation] created). Test/
  /// offline-demo hook.
  void proposeAction({
    String? conversationId,
    required String kind,
    required String summary,
    required Map<String, dynamic> fields,
  }) {
    final convo = _conversations[conversationId ?? _defaultConversationId];
    if (convo == null) return;
    final (id, createdAt) = _next();
    convo.messages.add(
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
    convo.updatedAt = createdAt;
    _emitConversations();
    convo.controller.add(List.unmodifiable(convo.messages));
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) async {
    final convo = _conversations[conversationId];
    if (convo == null) return;
    final action = _resolve(convo, actionId, AiActionStatus.applied);
    if (action == null) return;
    final (id, createdAt) = _next();
    convo.messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        content: _resultLine(action),
        createdAt: createdAt,
      ),
    );
    convo.updatedAt = createdAt;
    _emitConversations();
    convo.controller.add(List.unmodifiable(convo.messages));
  }

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) async {
    final convo = _conversations[conversationId];
    if (convo == null) return;
    final action = _resolve(convo, actionId, AiActionStatus.cancelled);
    if (action == null) return;
    final (id, createdAt) = _next();
    convo.messages.add(
      AiMessage(
        id: id,
        role: AiRole.assistant,
        content: "Okay — I won't add that.",
        createdAt: createdAt,
      ),
    );
    convo.updatedAt = createdAt;
    _emitConversations();
    convo.controller.add(List.unmodifiable(convo.messages));
  }

  /// Offline-testable stand-in for the real `aiImportWorkoutPlan` callable —
  /// delegates to [_importWorkoutPlanImpl], which defaults to
  /// [_defaultImportWorkoutPlan] (a canned success, ignoring [pdfBytes]
  /// entirely) but can be overridden at construction to script any outcome
  /// (accepted, rejected, or a thrown technical error) for tests that need
  /// to exercise those paths without a live backend.
  @override
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List pdfBytes,
  }) => _importWorkoutPlanImpl(pdfBytes);

  /// Offline-testable stand-in for the real `aiTranscribe` callable —
  /// delegates to [_transcribeImpl], which defaults to
  /// [_defaultTranscribe] (a canned transcript, ignoring the audio entirely)
  /// but can be overridden at construction to script any outcome (a
  /// transcript or a typed failure) for tests that need to exercise those
  /// paths without a live backend.
  @override
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  }) => _transcribeImpl(audioBytes, mimeType, languageHint);

  /// A canned, deterministic transcript. Ignores its arguments entirely
  /// (this fake never actually transcribes audio).
  static Future<SttOutcome> _defaultTranscribe(
    Uint8List audioBytes,
    String mimeType,
    String? languageHint,
  ) async {
    return const SttTranscribed(text: "This is a placeholder transcript.");
  }

  /// A canned, deterministic extraction. Ignores [pdfBytes] entirely (this
  /// fake never actually reads a PDF); a real upload always yields the same
  /// small two-day sample so the review screen is buildable/testable without
  /// Firebase.
  static Future<WorkoutImportOutcome> _defaultImportWorkoutPlan(
    Uint8List pdfBytes,
  ) async {
    return const WorkoutImportAccepted(
      WorkoutImportResult(
        planName: 'Imported Split',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(
                name: 'Bench Press',
                muscleGroup: 'Chest',
                sets: 3,
                repsMin: 8,
                repsMax: 12,
                toFailure: false,
              ),
            ],
          ),
          ImportedDay(
            slot: 'B',
            label: 'Pull',
            exercises: [
              ImportedExercise(
                name: 'Lat Pulldown',
                muscleGroup: 'Back',
                sets: 3,
                repsMin: 8,
                repsMax: 12,
                toFailure: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Flips a still-pending action to [status] in place; returns it, or null if
  /// missing or already resolved (idempotent).
  AiPendingAction? _resolve(
    _FakeConversation convo,
    String actionId,
    AiActionStatus status,
  ) {
    final i = convo.messages.indexWhere(
      (m) => m.pendingAction?.actionId == actionId,
    );
    if (i == -1) return null;
    final action = convo.messages[i].pendingAction!;
    if (!action.isPending) return null;
    convo.messages[i] = convo.messages[i].copyWith(
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

  void dispose() {
    for (final convo in _conversations.values) {
      convo.controller.close();
    }
    _conversationsController.close();
  }
}
