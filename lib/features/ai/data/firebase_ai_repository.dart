import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/ai_message.dart';
import '../domain/ai_pending_action.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_role.dart';
import '../domain/ai_turn_event.dart';

/// The real [AiRepository], backed by Firestore's
/// `users/{uid}/aiConversations` (+ nested `messages`) and the `aiChat`
/// callable Cloud Function (`functions/index.js`, orchestrated by
/// `functions/ai/gateway.js`). This is the *only* place Firestore/Functions
/// SDK types are allowed for this feature — everything above consumes the
/// domain [AiMessage] model.
///
/// The client never writes messages itself — Firestore rules forbid it
/// (`users/{uid}/aiConversations/{id}/messages` is server-write-only, see
/// `firestore.rules`). [send] only invokes `aiChat`, which persists both the
/// user message and the assistant's reply; both then surface via
/// [watchMessages].
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes [watchMessages] whenever the uid
/// changes (including to/from signed-out).
class FirebaseAiRepository implements AiRepository {
  FirebaseAiRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    required this.uidSource,
    Future<void> Function(String conversationId, String message)?
    invokeChat,
    Future<void> Function(String conversationId, String message,
        void Function(AiTurnEvent event) onEvent)?
    invokeChatStream,
    Future<void> Function(String name, String conversationId, String actionId)?
    invokeAction,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _invokeChat = invokeChat ?? _defaultInvokeChat(functions),
       _invokeChatStream =
           invokeChatStream ?? _defaultInvokeChatStream(functions),
       _invokeAction = invokeAction ?? _defaultInvokeAction(functions);

  final FirebaseFirestore _firestore;
  final UidSource uidSource;
  final Future<void> Function(String conversationId, String message)
  _invokeChat;
  final Future<void> Function(String conversationId, String message,
      void Function(AiTurnEvent event) onEvent) _invokeChatStream;
  final Future<void> Function(String name, String conversationId,
      String actionId) _invokeAction;

  String? _cachedConversationId;

  /// The default `send` invoker. Resolves [FirebaseFunctions] **lazily inside
  /// the returned closure** (never at construction), so the repo can be built
  /// — and unit-tested with a fake Firestore — without a live Firebase app.
  static Future<void> Function(String conversationId, String message)
  _defaultInvokeChat(FirebaseFunctions? functions) {
    return (conversationId, message) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable('aiChat').call({
        'conversationId': conversationId,
        'message': message,
      });
    };
  }

  /// The default streaming `send` invoker: consumes `aiChat` over callable
  /// streaming (`httpsCallable.stream()`), forwarding each phase/delta chunk to
  /// [onEvent]. The terminating `Result` is ignored — the durable user and
  /// assistant messages arrive via [watchMessages], same as the buffered path.
  /// Like [_defaultInvokeChat], resolves [FirebaseFunctions] lazily.
  static Future<void> Function(String conversationId, String message,
      void Function(AiTurnEvent event) onEvent) _defaultInvokeChatStream(
    FirebaseFunctions? functions,
  ) {
    return (conversationId, message, onEvent) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final stream = f.httpsCallable('aiChat').stream({
        'conversationId': conversationId,
        'message': message,
      });
      await for (final response in stream) {
        if (response is Chunk) {
          final event = aiTurnEventFromChunk(response.partialData);
          if (event != null) onEvent(event);
        }
      }
    };
  }

  /// The default confirm/cancel invoker — calls `aiConfirmAction` or
  /// `aiCancelAction`. Like [_defaultInvokeChat], resolves [FirebaseFunctions]
  /// lazily so the repo builds without a live Firebase app.
  static Future<void> Function(String name, String conversationId,
      String actionId) _defaultInvokeAction(FirebaseFunctions? functions) {
    return (name, conversationId, actionId) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable(name).call({
        'conversationId': conversationId,
        'actionId': actionId,
      });
    };
  }

  @override
  Future<String> ensureConversation() async {
    final uid = _requireUid();
    if (_cachedConversationId != null) return _cachedConversationId!;

    final existing = await _conversationsCollection(
      uid,
    ).orderBy('updatedAt', descending: true).limit(1).get();
    if (existing.docs.isNotEmpty) {
      _cachedConversationId = existing.docs.first.id;
      return _cachedConversationId!;
    }

    final now = Timestamp.fromDate(DateTime.now());
    final ref = await _conversationsCollection(uid).add({
      'title': 'Ask',
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': 1,
    });
    _cachedConversationId = ref.id;
    return ref.id;
  }

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) {
    late final StreamController<List<AiMessage>> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;

    void onUidChanged(String? uid) {
      querySub?.cancel();
      if (uid == null) {
        controller.add(const []);
        return;
      }
      querySub = _messagesCollection(uid, conversationId)
          .orderBy('createdAt')
          .snapshots()
          .listen((snapshot) {
            controller.add(snapshot.docs.map(_fromDoc).toList(growable: false));
          }, onError: (e, s) => controller.addError(e, s));
    }

    controller = StreamController<List<AiMessage>>.broadcast(
      onListen: () => uidSub = _uidWithInitial().listen(onUidChanged),
      onCancel: () {
        uidSub?.cancel();
        uidSub = null;
        querySub?.cancel();
        querySub = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    // Stream only when the caller wants live events; otherwise the plain
    // `.call()` path keeps the buffered behavior (and its cheaper transport).
    return onEvent == null
        ? _invokeChat(conversationId, trimmed)
        : _invokeChatStream(conversationId, trimmed, onEvent);
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) => _invokeAction('aiConfirmAction', conversationId, actionId);

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) => _invokeAction('aiCancelAction', conversationId, actionId);

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirebaseAiRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _conversationsCollection(
    String uid,
  ) => _firestore.collection('users').doc(uid).collection('aiConversations');

  CollectionReference<Map<String, dynamic>> _messagesCollection(
    String uid,
    String conversationId,
  ) => _conversationsCollection(uid).doc(conversationId).collection('messages');

  AiMessage _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return AiMessage(
      id: doc.id,
      role: aiRoleFromName(data['role'] as String?),
      content: data['content'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      pendingAction: _pendingActionFrom(data),
    );
  }

  /// Maps an `action_proposal` message (ADR-003) into an [AiPendingAction]; the
  /// message doc carries `actionId`, `actionKind`, `fields`, `status`, and
  /// `expiresAt`. The card renders from the server-stored [status], so it
  /// reflects the true resolution — applied/cancelled/expired — on reopen and
  /// however the action was resolved (a card tap, a typed reply, or expiry), not
  /// just an optimistic client flag. A still-`pending` proposal whose `expiresAt`
  /// has passed is rendered as expired here, so a stale card doesn't keep
  /// offering Confirm/Cancel until it's tapped. Legacy messages without a
  /// `status` default to pending.
  AiPendingAction? _pendingActionFrom(Map<String, dynamic> data) {
    if (data['kind'] != 'action_proposal') return null;
    final actionId = data['actionId'] as String?;
    final actionKind = data['actionKind'] as String?;
    if (actionId == null || actionKind == null) return null;
    final rawFields = data['fields'];
    final stored = aiActionStatusFromName(data['status'] as String?);
    final expiresAtRaw = data['expiresAt'];
    final expiresAt = expiresAtRaw is Timestamp ? expiresAtRaw.toDate() : null;
    final status = stored == AiActionStatus.pending &&
            expiresAt != null &&
            expiresAt.isBefore(DateTime.now())
        ? AiActionStatus.expired
        : stored;
    return AiPendingAction(
      actionId: actionId,
      kind: actionKind,
      summary: data['content'] as String? ?? '',
      fields: rawFields is Map
          ? Map<String, dynamic>.from(rawFields)
          : const <String, dynamic>{},
      status: status,
    );
  }
}
