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
import '../../workout/domain/workout_import_outcome.dart';
import '../../workout/domain/workout_import_result.dart';
import '../domain/ai_conversation.dart';
import '../domain/ai_message.dart';
import '../domain/ai_pending_action.dart';
import '../domain/ai_repository.dart';
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

class FirebaseAiRepository implements AiRepository {
  FirebaseAiRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    required this.uidSource,
    Future<void> Function(
      String conversationId,
      String message,
      String responseStyle,
      String? clientTurnId,
    )?
    invokeChat,
    Future<void> Function(
      String conversationId,
      String message,
      String responseStyle,
      String? clientTurnId,
      void Function(AiTurnEvent event) onEvent,
    )?
    invokeChatStream,
    Future<void> Function(String name, String conversationId, String actionId)?
    invokeAction,
    Future<WorkoutImportOutcome> Function(
      Uint8List fileBytes,
      String mimeType,
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
    String? clientTurnId,
  )
  _invokeChat;
  final Future<void> Function(
    String conversationId,
    String message,
    String responseStyle,
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
    Uint8List fileBytes,
    String mimeType,
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
    String? clientTurnId,
  )
  _defaultInvokeChat(FirebaseFunctions? functions) {
    return (conversationId, message, responseStyle, clientTurnId) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable('aiChat').call({
        'conversationId': conversationId,
        'message': message,
        'responseStyle': responseStyle,
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
    String? clientTurnId,
    void Function(AiTurnEvent event) onEvent,
  )
  _defaultInvokeChatStream(FirebaseFunctions? functions) {
    return (
      conversationId,
      message,
      responseStyle,
      clientTurnId,
      onEvent,
    ) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final stream = f.httpsCallable('aiChat').stream({
        'conversationId': conversationId,
        'message': message,
        'responseStyle': responseStyle,
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
  /// with the file base64-encoded. Like [_defaultInvokeChat], resolves
  /// [FirebaseFunctions] lazily so the repo builds without a live Firebase
  /// app.
  static Future<WorkoutImportOutcome> Function(
    Uint8List fileBytes,
    String mimeType,
    void Function(ImportProgress)? onProgress,
  )
  _defaultInvokeImport(FirebaseFunctions? functions) {
    return (fileBytes, mimeType, onProgress) async {
      final f =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final payload = {
        'fileBase64': base64Encode(fileBytes),
        'mimeType': mimeType,
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
  static Future<T> _streamImport<T>(
    Stream<StreamResponse> stream,
    void Function(ImportProgress) onProgress,
    T Function(Object?) parse,
  ) async {
    Object? data;
    await for (final response in stream) {
      // `is Chunk` rather than a switch on the sealed type: the terminating
      // variant's name collides with other `Result` types in scope, and the
      // chat stream above already reads the stream this way.
      if (response is Chunk) {
        final progress = ImportProgress.fromChunk(response.partialData);
        if (progress != null && !progress.isEmpty) onProgress(progress);
      } else {
        data = (response as dynamic).data;
      }
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
    String? clientTurnId,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    // Stream only when the caller wants live events; otherwise the plain
    // `.call()` path keeps the buffered behavior (and its cheaper transport).
    return onEvent == null
        ? _invokeChat(conversationId, trimmed, responseStyle, clientTurnId)
        : _invokeChatStream(
            conversationId,
            trimmed,
            responseStyle,
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
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List fileBytes,
    required String mimeType,
    void Function(ImportProgress progress)? onProgress,
  }) => _invokeImport(fileBytes, mimeType, onProgress);

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
      clientTurnId: data['clientTurnId'] as String?,
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
