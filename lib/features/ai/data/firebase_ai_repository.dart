import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/uid_source.dart';
import '../../diet/domain/diet_import_input.dart';
import '../../diet/domain/diet_import_outcome.dart';
import '../../diet/domain/diet_import_result.dart';
import '../../diet/domain/nutrition_targets.dart';
import '../../diet/domain/plan_preferences.dart';
import '../../workout/domain/workout_import_input.dart';
import '../../workout/domain/workout_import_outcome.dart';
import '../../workout/domain/workout_import_result.dart';
import '../domain/ai_conversation.dart';
import '../domain/ai_choice_request.dart';
import '../domain/ai_input_request.dart';
import '../domain/ai_message.dart';
import '../domain/ai_model_selection.dart';
import '../domain/ai_pending_action.dart';
import '../domain/ai_repository.dart';
import '../domain/ai_usage_summary.dart';
import '../domain/import_progress.dart';
import '../domain/ai_response_style.dart';
import '../domain/ai_role.dart';
import '../domain/ai_turn_event.dart';
import '../domain/stt_error.dart';
import '../domain/stt_outcome.dart';

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
/// The device's own clock, as the `aiChat` gateway needs it: the UTC offset in
/// whole minutes plus the short zone name ("EEST") for the coach to quote.
///
/// Cloud Functions run in UTC, but this app writes `dietEntries.dayKey` from
/// the **device's** calendar date. Without this the server resolved a
/// different "today" from the one on screen for every user east or west of
/// UTC — a UTC+3 user asking anything between local midnight and 03:00 got
/// yesterday's diet entries and yesterday's weekday plan slot. Sent per turn
/// rather than stored, so it follows the user across timezones and DST with
/// no dependency on a timezone package.
Map<String, Object?> clientClockFields([DateTime? now]) {
  final at = now ?? DateTime.now();
  return {
    'utcOffsetMinutes': at.timeZoneOffset.inMinutes,
    'timeZoneName': at.timeZoneName,
  };
}

/// A mutable per-provider accumulator for [FirebaseAiRepository.usageByProvider].
class _UsageAcc {
  int tokensIn = 0;
  int tokensOut = 0;
  int turns = 0;
  double costUsd = 0;
}

/// The routing-layer provider name for a logged `model` id, for turns written
/// before the backend recorded an explicit `provider` field. Everything Claude
/// is 'anthropic'; everything Gemini is 'gemini'; anything else (or missing)
/// defaults to 'anthropic', since every pre-`provider` turn was Anthropic.
String _providerFromModel(String? model) {
  final m = (model ?? '').toLowerCase();
  if (m.startsWith('gemini')) return 'gemini';
  if (m.startsWith('claude')) return 'anthropic';
  return 'anthropic';
}

/// Firestore may hand a number back as int or double; coerce to int safely.
int _asInt(Object? v) => v is num ? v.toInt() : 0;

/// Firestore may hand a number back as int or double; coerce to double safely.
double _asDouble(Object? v) => v is num ? v.toDouble() : 0;

class FirebaseAiRepository implements AiRepository {
  FirebaseAiRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    required this.uidSource,
    Future<void> Function(
      String conversationId,
      String message,
      String responseStyle,
      String provider,
      String? clientTurnId,
    )?
    invokeChat,
    Future<void> Function(
      String conversationId,
      String message,
      String responseStyle,
      String provider,
      String? clientTurnId,
      void Function(AiTurnEvent event) onEvent,
    )?
    invokeChatStream,
    Future<void> Function(String name, String conversationId, String actionId)?
    invokeAction,
    Future<WorkoutImportOutcome> Function(
      WorkoutImportInput input,
      void Function(ImportProgress)? onProgress,
    )?
    invokeImport,
    Future<DietImportOutcome> Function(
      DietImportInput input,
      void Function(ImportProgress)? onProgress,
    )?
    invokeDietImport,
    Future<DietImportOutcome> Function(
      PlanPreferences preferences,
      NutritionTargets? targets,
    )?
    invokeDietGenerate,
    Future<SttOutcome> Function(
      Uint8List audioBytes,
      String mimeType,
      String? languageHint,
    )?
    invokeTranscribe,
    Future<void> Function(String conversationId)? invokeDelete,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _invokeChat = invokeChat ?? _defaultInvokeChat(functions),
       _invokeChatStream =
           invokeChatStream ?? _defaultInvokeChatStream(functions),
       _invokeAction = invokeAction ?? _defaultInvokeAction(functions),
       _invokeImport = invokeImport ?? _defaultInvokeImport(functions),
       _invokeDietImport =
           invokeDietImport ?? _defaultInvokeDietImport(functions),
       _invokeDietGenerate =
           invokeDietGenerate ?? _defaultInvokeDietGenerate(functions),
       _invokeTranscribe =
           invokeTranscribe ?? _defaultInvokeTranscribe(functions),
       _invokeDelete = invokeDelete ?? _defaultInvokeDelete(functions);

  final FirebaseFirestore _firestore;
  final UidSource uidSource;
  final Future<void> Function(
    String conversationId,
    String message,
    String responseStyle,
    String provider,
    String? clientTurnId,
  )
  _invokeChat;
  final Future<void> Function(
    String conversationId,
    String message,
    String responseStyle,
    String provider,
    String? clientTurnId,
    void Function(AiTurnEvent event) onEvent,
  )
  _invokeChatStream;
  final Future<void> Function(
    String name,
    String conversationId,
    String actionId,
  )
  _invokeAction;
  final Future<WorkoutImportOutcome> Function(
    WorkoutImportInput input,
    void Function(ImportProgress)? onProgress,
  )
  _invokeImport;
  final Future<DietImportOutcome> Function(
    DietImportInput input,
    void Function(ImportProgress)? onProgress,
  )
  _invokeDietImport;
  final Future<DietImportOutcome> Function(
    PlanPreferences preferences,
    NutritionTargets? targets,
  )
  _invokeDietGenerate;
  final Future<SttOutcome> Function(
    Uint8List audioBytes,
    String mimeType,
    String? languageHint,
  )
  _invokeTranscribe;
  final Future<void> Function(String conversationId) _invokeDelete;

  String? _cachedConversationId;

  /// The default `send` invoker. Resolves [FirebaseFunctions] **lazily inside
  /// the returned closure** (never at construction), so the repo can be built
  /// — and unit-tested with a fake Firestore — without a live Firebase app.
  static Future<void> Function(
    String conversationId,
    String message,
    String responseStyle,
    String provider,
    String? clientTurnId,
  )
  _defaultInvokeChat(FirebaseFunctions? functions) {
    return (conversationId, message, responseStyle, provider, clientTurnId) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable('aiChat').call({
        'conversationId': conversationId,
        'message': message,
        'responseStyle': responseStyle,
        'provider': provider,
        'clientTurnId': ?clientTurnId,
        ...clientClockFields(),
      });
    };
  }

  /// The default streaming `send` invoker: consumes `aiChat` over callable
  /// streaming (`httpsCallable.stream()`), forwarding each phase/delta chunk to
  /// [onEvent]. The terminating `Result` is ignored — the durable user and
  /// assistant messages arrive via [watchMessages], same as the buffered path.
  /// Like [_defaultInvokeChat], resolves [FirebaseFunctions] lazily.
  ///
  /// The payload carries `acceptsStreaming: true` explicitly — the server
  /// gates its per-token work on that flag, and the transport alone doesn't
  /// set it. Without it the turn silently degrades to buffered, dropping the
  /// whole reply on screen at once.
  static Future<void> Function(
    String conversationId,
    String message,
    String responseStyle,
    String provider,
    String? clientTurnId,
    void Function(AiTurnEvent event) onEvent,
  )
  _defaultInvokeChatStream(FirebaseFunctions? functions) {
    return (
      conversationId,
      message,
      responseStyle,
      provider,
      clientTurnId,
      onEvent,
    ) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final stream = f.httpsCallable('aiChat').stream({
        'conversationId': conversationId,
        'message': message,
        'responseStyle': responseStyle,
        'provider': provider,
        'acceptsStreaming': true,
        'clientTurnId': ?clientTurnId,
        ...clientClockFields(),
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
  static Future<void> Function(
    String name,
    String conversationId,
    String actionId,
  )
  _defaultInvokeAction(FirebaseFunctions? functions) {
    return (name, conversationId, actionId) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable(name).call({
        'conversationId': conversationId,
        'actionId': actionId,
      });
    };
  }

  /// The default `deleteConversation` invoker — calls `aiDeleteConversation`.
  /// Like [_defaultInvokeChat], resolves [FirebaseFunctions] lazily so the
  /// repo builds without a live Firebase app.
  static Future<void> Function(String conversationId) _defaultInvokeDelete(
    FirebaseFunctions? functions,
  ) {
    return (conversationId) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable('aiDeleteConversation').call({
        'conversationId': conversationId,
      });
    };
  }

  /// The default `importWorkoutPlan` invoker — calls `aiImportWorkoutPlan`
  /// with either the file base64-encoded or the user's description as text.
  /// Like [_defaultInvokeChat], resolves [FirebaseFunctions] lazily so the
  /// repo builds without a live Firebase app. The payload carries exactly one
  /// kind of material; the sealed [WorkoutImportInput] makes both-at-once
  /// unrepresentable here, and the server refuses it too. Mirrors
  /// [_defaultInvokeDietImport].
  static Future<WorkoutImportOutcome> Function(
    WorkoutImportInput input,
    void Function(ImportProgress)? onProgress,
  )
  _defaultInvokeImport(FirebaseFunctions? functions) {
    return (input, onProgress) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final payload = <String, dynamic>{
        ...switch (input) {
          WorkoutImportDocument(:final bytes, :final mimeType) => {
            'fileBase64': base64Encode(bytes),
            'mimeType': mimeType,
          },
          WorkoutImportDescription(:final text) => {'text': text},
        },
        if (onProgress != null) 'acceptsStreaming': true,
      };
      final callable = f.httpsCallable('aiImportWorkoutPlan');
      if (onProgress == null) {
        return _importOutcomeFromJson((await callable.call(payload)).data);
      }
      return _streamImport(
        callable.stream(payload),
        onProgress,
        _importOutcomeFromJson,
      );
    };
  }

  /// Drives a streaming import callable: forwards each `progress` chunk and
  /// resolves from the terminating result.
  ///
  /// The result must come from the stream's own `Result`, not from a second
  /// buffered call — an import is an expensive whole-document model call, and
  /// calling twice would pay for it twice.
  ///
  /// The terminating variant is `Result`, whose payload sits one level down
  /// (`.result.data`, an `HttpsCallableResult`) — never `.data` on the
  /// response itself. Both branches are statically typed on purpose: reading
  /// that payload through `dynamic` is exactly how the getter silently went
  /// missing and turned every successful extraction into "couldn't read that
  /// plan" on screen.
  static Future<T> _streamImport<T>(
    Stream<StreamResponse> stream,
    void Function(ImportProgress) onProgress,
    T Function(Object?) parse,
  ) async {
    Object? data;
    var resolved = false;
    await for (final response in stream) {
      switch (response) {
        case Chunk(:final partialData):
          final progress = ImportProgress.fromChunk(partialData);
          if (progress != null && !progress.isEmpty) onProgress(progress);
        case Result(:final result):
          data = result.data;
          resolved = true;
      }
    }
    if (!resolved) {
      // The stream ended without its terminating result — a truncated
      // response, not a verdict on the document. Throwing keeps that an
      // error the caller can report as one, instead of parsing `null` into
      // a fake "this isn't a valid plan" rejection.
      throw StateError('Import stream ended without a result.');
    }
    return parse(data);
  }

  /// The default `importDietPlan` invoker — calls `aiImportDietPlan` with
  /// either the file base64-encoded or the user's description as text.
  /// Mirrors [_defaultInvokeImport] otherwise.
  ///
  /// The payload carries exactly one kind of material; the server refuses
  /// both-at-once, and the sealed [DietImportInput] makes it unrepresentable
  /// here in the first place.
  static Future<DietImportOutcome> Function(
    DietImportInput input,
    void Function(ImportProgress)? onProgress,
  )
  _defaultInvokeDietImport(FirebaseFunctions? functions) {
    return (input, onProgress) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final payload = <String, dynamic>{
        ...switch (input) {
          DietImportDocument(:final bytes, :final mimeType) => {
            'fileBase64': base64Encode(bytes),
            'mimeType': mimeType,
          },
          DietImportDescription(:final text) => {'text': text},
        },
        if (onProgress != null) 'acceptsStreaming': true,
      };
      final callable = f.httpsCallable('aiImportDietPlan');
      if (onProgress == null) {
        return _dietImportOutcomeFromJson((await callable.call(payload)).data);
      }
      return _streamImport(
        callable.stream(payload),
        onProgress,
        _dietImportOutcomeFromJson,
      );
    };
  }

  /// The default `generateDietPlan` invoker — calls `aiGenerateDietPlan` with
  /// the preferences and, when the user has one, their target. The response
  /// shape is identical to the importer's, so it reuses the same parser.
  static Future<DietImportOutcome> Function(
    PlanPreferences preferences,
    NutritionTargets? targets,
  )
  _defaultInvokeDietGenerate(FirebaseFunctions? functions) {
    return (preferences, targets) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final result = await f.httpsCallable('aiGenerateDietPlan').call({
        'preferences': preferences.toPayload(),
        if (targets != null)
          'targets': {
            'calories': targets.calories,
            'proteinG': targets.proteinG,
            'goal': targets.goal.name,
          },
      });
      return _dietImportOutcomeFromJson(result.data);
    };
  }

  /// The default `transcribe` invoker — calls `aiTranscribe`
  /// (`functions/ai/speech/gateway.js`) with the audio base64-encoded. Like
  /// [_defaultInvokeChat], resolves [FirebaseFunctions] lazily so the repo
  /// builds without a live Firebase app. Never throws: every failure —
  /// technical or a typed `SpeechError` from the server — maps to
  /// [SttFailed], mirroring [_importOutcomeFromJson]'s never-throws contract
  /// for the analogous `aiImportWorkoutPlan` seam.
  static Future<SttOutcome> Function(
    Uint8List audioBytes,
    String mimeType,
    String? languageHint,
  )
  _defaultInvokeTranscribe(FirebaseFunctions? functions) {
    return (audioBytes, mimeType, languageHint) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      try {
        final result = await f.httpsCallable('aiTranscribe').call({
          'audioBase64': base64Encode(audioBytes),
          'mimeType': mimeType,
          'languageHint': ?languageHint,
        });
        return _sttOutcomeFromJson(result.data);
      } on FirebaseFunctionsException catch (e) {
        return SttFailed(
          _sttErrorFromException(e),
          e.message ?? _genericSttFailureMessage,
        );
      } catch (_) {
        return const SttFailed(SttError.unknown, _genericSttFailureMessage);
      }
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
  Future<String> createConversation({String? title}) async {
    final uid = _requireUid();
    final now = Timestamp.fromDate(DateTime.now());
    final ref = await _conversationsCollection(uid).add({
      'title': (title == null || title.trim().isEmpty)
          ? 'New chat'
          : title.trim(),
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': 1,
    });
    return ref.id;
  }

  @override
  Future<void> renameConversation(String id, String title) async {
    final uid = _requireUid();
    await _conversationsCollection(uid).doc(id).update({'title': title});
  }

  @override
  Future<void> deleteConversation(String id) => _invokeDelete(id);

  @override
  Stream<List<AiConversation>> watchConversations() {
    late final StreamController<List<AiConversation>> controller;
    StreamSubscription<String?>? uidSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;

    void onUidChanged(String? uid) {
      querySub?.cancel();
      if (uid == null) {
        controller.add(const []);
        return;
      }
      querySub = _conversationsCollection(uid)
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            controller.add(
              snapshot.docs.map(_conversationFromDoc).toList(growable: false),
            );
          }, onError: (e, s) => controller.addError(e, s));
    }

    controller = StreamController<List<AiConversation>>.broadcast(
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
  Future<AiConversation?> latestConversation() async {
    final uid = uidSource.currentUid();
    if (uid == null) return null;
    final snapshot = await _conversationsCollection(
      uid,
    ).orderBy('updatedAt', descending: true).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    return _conversationFromDoc(snapshot.docs.first);
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
    String responseStyle = kDefaultResponseStyle,
    String modelSelection = kDefaultAiModelSelection,
    String? clientTurnId,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    // Guard the wire value: never trust a round-tripped/stale selection to
    // reach the gateway — the server also defaults unknowns to 'auto', but the
    // client shouldn't send a value it wouldn't accept back.
    final provider = validAiModelSelection(modelSelection);
    // Stream only when the caller wants live events; otherwise the plain
    // `.call()` path keeps the buffered behavior (and its cheaper transport).
    return onEvent == null
        ? _invokeChat(conversationId, trimmed, responseStyle, provider,
            clientTurnId)
        : _invokeChatStream(
            conversationId,
            trimmed,
            responseStyle,
            provider,
            clientTurnId,
            onEvent,
          );
  }

  @override
  Future<String> getResponseStyle() async {
    final uid = uidSource.currentUid();
    if (uid == null) return kDefaultResponseStyle;
    final doc = await _aiSettingsDoc(uid).get();
    return validResponseStyle(doc.data()?['responseStyle'] as String?);
  }

  @override
  Future<void> setResponseStyle(String style) async {
    final uid = _requireUid();
    await _aiSettingsDoc(
      uid,
    ).set({'responseStyle': style}, SetOptions(merge: true));
  }

  @override
  Future<String> getModelSelection() async {
    final uid = uidSource.currentUid();
    if (uid == null) return kDefaultAiModelSelection;
    final doc = await _aiSettingsDoc(uid).get();
    return validAiModelSelection(doc.data()?['provider'] as String?);
  }

  @override
  Future<void> setModelSelection(String selection) async {
    final uid = _requireUid();
    await _aiSettingsDoc(
      uid,
    ).set({'provider': selection}, SetOptions(merge: true));
  }

  @override
  Future<List<AiProviderUsage>> usageByProvider() async {
    final uid = uidSource.currentUid();
    if (uid == null) return const [];
    final snapshot = await _aiUsageCollection(uid).get();
    // Accumulate per provider. A turn logged before the backend recorded a
    // `provider` field is attributed by its `model` id (all legacy turns were
    // Anthropic/Claude, so the model prefix is a reliable fallback).
    final acc = <String, _UsageAcc>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final provider = (data['provider'] as String?) ??
          _providerFromModel(data['model'] as String?);
      final a = acc.putIfAbsent(provider, _UsageAcc.new);
      a.tokensIn += _asInt(data['tokensIn']);
      a.tokensOut += _asInt(data['tokensOut']);
      a.costUsd += _asDouble(data['costUsd']);
      a.turns += 1;
    }
    final list = acc.entries
        .map(
          (e) => AiProviderUsage(
            provider: e.key,
            tokensIn: e.value.tokensIn,
            tokensOut: e.value.tokensOut,
            turns: e.value.turns,
            costUsd: e.value.costUsd,
          ),
        )
        .toList()
      ..sort((a, b) => b.tokensTotal.compareTo(a.tokensTotal));
    return list;
  }

  CollectionReference<Map<String, dynamic>> _aiUsageCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('aiUsage');

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

  @override
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) => _invokeImport(input, onProgress);

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) => _invokeDietImport(input, onProgress);

  @override
  Future<DietImportOutcome> generateDietPlan({
    required PlanPreferences preferences,
    NutritionTargets? targets,
  }) => _invokeDietGenerate(preferences, targets);

  @override
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  }) => _invokeTranscribe(audioBytes, mimeType, languageHint);

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

  DocumentReference<Map<String, dynamic>> _aiSettingsDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('settings').doc('ai');

  AiConversation _conversationFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    return AiConversation(
      id: doc.id,
      title: data['title'] as String? ?? 'New chat',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }

  AiMessage _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return AiMessage(
      id: doc.id,
      role: aiRoleFromName(data['role'] as String?),
      content: data['content'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      pendingAction: _pendingActionFrom(data),
      choiceRequest: _choiceRequestFrom(data),
      inputRequest: _inputRequestFrom(data),
      clientTurnId: data['clientTurnId'] as String?,
    );
  }

  /// Maps an `input_request` message (Ask elicitation Phase 2) into an
  /// [AiInputRequest]; the doc carries `requestId` and a `fields` map of
  /// `{fields: [{key, label, type, unit?, options?, required}]}`. A malformed
  /// or fieldless card returns null so it falls back to a plain text bubble
  /// (the `content` still holds the ask), never a broken empty form.
  AiInputRequest? _inputRequestFrom(Map<String, dynamic> data) {
    if (data['kind'] != 'input_request') return null;
    final requestId = data['requestId'] as String?;
    if (requestId == null) return null;
    final fields = data['fields'];
    if (fields is! Map) return null;
    final rawFields = fields['fields'];
    if (rawFields is! List) return null;
    final parsed = <AiInputField>[];
    for (final raw in rawFields) {
      if (raw is! Map) continue;
      final key = raw['key'] as String?;
      final label = raw['label'] as String?;
      if (key == null || key.isEmpty || label == null || label.isEmpty) {
        continue;
      }
      parsed.add(
        AiInputField(
          key: key,
          label: label,
          type: AiInputFieldType.fromName(raw['type'] as String?),
          unit: raw['unit'] as String?,
          options: _optionsFrom(raw['options']),
          required: raw['required'] != false,
        ),
      );
    }
    if (parsed.isEmpty) return null;
    return AiInputRequest(
      requestId: requestId,
      prompt: data['content'] as String? ?? '',
      fields: parsed,
    );
  }

  /// Parses a raw `[{value, label}]` list into [AiChoiceOption]s, dropping any
  /// entry without a usable label. Shared by choice questions and a
  /// `choice`-type input field.
  List<AiChoiceOption> _optionsFrom(Object? raw) {
    if (raw is! List) return const [];
    final options = <AiChoiceOption>[];
    for (final o in raw) {
      if (o is! Map) continue;
      final label = o['label'] as String?;
      if (label == null || label.isEmpty) continue;
      options.add(
        AiChoiceOption(value: (o['value'] as String?) ?? label, label: label),
      );
    }
    return options;
  }

  /// Maps a `choice_request` message (Ask elicitation, Phase 1) into an
  /// [AiChoiceRequest]; the message doc carries `requestId` and a `fields` map
  /// of `{options: [{value, label}], allowMultiple}`. A malformed or optionless
  /// card returns null so it falls back to a plain text bubble (the `content`
  /// still holds the question), never a broken empty chip row.
  AiChoiceRequest? _choiceRequestFrom(Map<String, dynamic> data) {
    if (data['kind'] != 'choice_request') return null;
    final requestId = data['requestId'] as String?;
    if (requestId == null) return null;
    final fields = data['fields'];
    if (fields is! Map) return null;
    final rawOptions = fields['options'];
    if (rawOptions is! List) return null;
    final options = <AiChoiceOption>[];
    for (final raw in rawOptions) {
      if (raw is! Map) continue;
      final label = raw['label'] as String?;
      if (label == null || label.isEmpty) continue;
      options.add(
        AiChoiceOption(value: (raw['value'] as String?) ?? label, label: label),
      );
    }
    if (options.length < 2) return null;
    return AiChoiceRequest(
      requestId: requestId,
      prompt: data['content'] as String? ?? '',
      options: options,
      allowMultiple: fields['allowMultiple'] == true,
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
    final status =
        stored == AiActionStatus.pending &&
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

/// Maps `aiImportWorkoutPlan`'s raw callable result (a platform-channel
/// `Map<Object?, Object?>`, not `Map<String, dynamic>`) into a
/// [WorkoutImportOutcome]. Mirrors `functions/ai/workout_import.js`'s return
/// shape exactly (`{ok: true, planName, days}` or `{ok: false, reason}`) —
/// that function already guarantees every field is present and well-typed
/// for the `ok: true` case, so this only needs to cast, not re-validate. A
/// missing/malformed `ok` field defaults to a rejection rather than risking
/// an empty plan silently importing.
WorkoutImportOutcome _importOutcomeFromJson(Object? data) {
  final map = data is Map ? data : const {};
  if (map['ok'] != true) {
    final reason =
        map['reason'] as String? ??
        "This file doesn't contain enough valid workout data to create a training plan.";
    return WorkoutImportRejected(reason);
  }
  final planName = map['planName'] as String? ?? 'Imported Split';
  final rawDays = map['days'];
  final days = rawDays is List
      ? [for (final d in rawDays) _importedDayFromJson(d)]
      : const <ImportedDay>[];
  return WorkoutImportAccepted(
    WorkoutImportResult(planName: planName, days: days),
  );
}

ImportedDay _importedDayFromJson(Object? data) {
  final map = data is Map ? data : const {};
  final rawExercises = map['exercises'];
  final exercises = rawExercises is List
      ? [for (final e in rawExercises) _importedExerciseFromJson(e)]
      : const <ImportedExercise>[];
  return ImportedDay(
    slot: map['slot'] as String? ?? '',
    label: map['label'] as String? ?? '',
    exercises: exercises,
  );
}

ImportedExercise _importedExerciseFromJson(Object? data) {
  final map = data is Map ? data : const {};
  return ImportedExercise(
    name: map['name'] as String? ?? '',
    muscleGroup: map['muscleGroup'] as String?,
    sets: (map['sets'] as num?)?.toInt() ?? 1,
    repsMin: (map['repsMin'] as num?)?.toInt(),
    repsMax: (map['repsMax'] as num?)?.toInt(),
    toFailure: map['toFailure'] == true,
    targetWeightKg: (map['targetWeightKg'] as num?)?.toDouble(),
    restSeconds: (map['restSeconds'] as num?)?.toInt(),
  );
}

/// Maps `aiImportDietPlan`'s raw callable result (a platform-channel
/// `Map<Object?, Object?>`, not `Map<String, dynamic>`) into a
/// [DietImportOutcome]. Mirrors `_importOutcomeFromJson` exactly — see that
/// function's doc for the shared reasoning (the server already guarantees
/// every field is present and well-typed for the `ok: true` case, so this
/// only needs to cast, not re-validate).
DietImportOutcome _dietImportOutcomeFromJson(Object? data) {
  final map = data is Map ? data : const {};
  if (map['ok'] != true) {
    final reason =
        map['reason'] as String? ??
        "This file doesn't contain enough valid diet data to create a plan.";
    return DietImportRejected(reason);
  }
  final planName = map['planName'] as String? ?? 'Imported Plan';
  final rawDays = map['days'];
  final days = rawDays is List
      ? [for (final d in rawDays) _importedDietDayFromJson(d)]
      : const <ImportedDietDay>[];
  return DietImportAccepted(DietImportResult(planName: planName, days: days));
}

ImportedDietDay _importedDietDayFromJson(Object? data) {
  final map = data is Map ? data : const {};
  final rawMeals = map['meals'];
  final meals = rawMeals is List
      ? [for (final m in rawMeals) _importedMealFromJson(m)]
      : const <ImportedMeal>[];
  return ImportedDietDay(
    weekday: (map['weekday'] as num?)?.toInt(),
    label: map['label'] as String? ?? '',
    meals: meals,
  );
}

ImportedMeal _importedMealFromJson(Object? data) {
  final map = data is Map ? data : const {};
  final rawItems = map['items'];
  final items = rawItems is List
      ? [for (final i in rawItems) _importedFoodItemFromJson(i)]
      : const <ImportedFoodItem>[];
  return ImportedMeal(label: map['label'] as String? ?? '', items: items);
}

ImportedFoodItem _importedFoodItemFromJson(Object? data) {
  final map = data is Map ? data : const {};
  return ImportedFoodItem(
    name: map['name'] as String? ?? '',
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    unit: map['unit'] as String? ?? '',
    calories: (map['calories'] as num?)?.toInt(),
    proteinG: (map['proteinG'] as num?)?.toDouble(),
    carbsG: (map['carbsG'] as num?)?.toDouble(),
    fatG: (map['fatG'] as num?)?.toDouble(),
    estimated: map['estimated'] == true,
  );
}

/// Shown when a transcription attempt fails for a reason with no
/// server-provided message (a bare network/platform exception, never a
/// `SpeechError` — those always carry their own user-presentable message).
const _genericSttFailureMessage =
    "Couldn't transcribe that — check your connection and try again.";

/// Maps `aiTranscribe`'s raw callable result (a platform-channel
/// `Map<Object?, Object?>`) into an [SttTranscribed]. Only reached on
/// success — `functions/ai/speech/gateway.js` never returns an `ok: false`
/// shape the way `aiImportWorkoutPlan` does; every failure there throws
/// instead, mapped by [_sttErrorFromException].
SttOutcome _sttOutcomeFromJson(Object? data) {
  final map = data is Map ? data : const {};
  return SttTranscribed(
    text: map['text'] as String? ?? '',
    detectedLanguage: map['detectedLanguage'] as String?,
    durationMs: (map['durationMs'] as num?)?.toInt(),
  );
}

/// Maps `aiTranscribe`'s thrown `HttpsError` into an [SttError]. The server
/// (`functions/index.js`'s `toSpeechHttpsError`) carries its precise
/// `SpeechError` code in `details.sttCode` — that's read first, since the
/// gRPC `code` alone is a coarser bucket (e.g. both `audio_too_large` and
/// `unsupported_audio_format` map to the wire code `invalid-argument`).
SttError _sttErrorFromException(FirebaseFunctionsException e) {
  final details = e.details;
  final sttCode = details is Map ? details['sttCode'] as String? : null;
  switch (sttCode) {
    case 'unsupported_audio_format':
      return SttError.unsupportedAudioFormat;
    case 'audio_too_large':
      return SttError.audioTooLarge;
    case 'transcription_failed':
      return SttError.transcriptionFailed;
    case 'provider_unavailable':
      return SttError.providerUnavailable;
    case 'timeout':
      return SttError.timeout;
  }
  // No (or an unrecognized) sttCode — fall back to the gRPC code.
  switch (e.code) {
    case 'unavailable':
      return SttError.providerUnavailable;
    case 'deadline-exceeded':
      return SttError.timeout;
    default:
      return SttError.unknown;
  }
}
