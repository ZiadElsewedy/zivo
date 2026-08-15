import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/ai_message.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_role.dart';

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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _invokeChat = invokeChat ?? _defaultInvokeChat(functions);

  final FirebaseFirestore _firestore;
  final UidSource uidSource;
  final Future<void> Function(String conversationId, String message)
  _invokeChat;

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
          });
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
  Future<void> send({required String conversationId, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    return _invokeChat(conversationId, trimmed);
  }

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
    );
  }
}
