import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/ai/data/firebase_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_pending_action.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/stt_error.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

void main() {
  group('FirebaseAiRepository', () {
    test('ensureConversation creates a conversation doc when none exists, '
        'and reuses it on a second call', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final id = await repo.ensureConversation();

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .doc(id)
          .get();
      final data = doc.data()!;
      expect(data['title'], 'Ask');
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
      expect(data['schemaVersion'], 1);

      final again = await repo.ensureConversation();
      expect(again, id);

      final snapshot = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('ensureConversation reuses an existing conversation found in '
        'Firestore (not just the in-memory cache)', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .doc('existing')
          .set({
            'title': 'Ask',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'schemaVersion': 1,
          });

      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      expect(await repo.ensureConversation(), 'existing');
    });

    test('watchMessages maps seeded message docs to AiMessages in createdAt '
        'order with correct roles', () async {
      final firestore = FakeFirebaseFirestore();
      final messages = firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .doc('conv-1')
          .collection('messages');

      await messages.doc('m2').set({
        'role': 'assistant',
        'content': 'Hi there!',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 1)),
        'schemaVersion': 1,
      });
      await messages.doc('m1').set({
        'role': 'user',
        'content': 'Hello',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0)),
        'schemaVersion': 1,
      });

      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final result = await repo.watchMessages('conv-1').first;
      expect(result, hasLength(2));
      expect(result[0].content, 'Hello');
      expect(result[0].role, AiRole.user);
      expect(result[1].content, 'Hi there!');
      expect(result[1].role, AiRole.assistant);
    });

    test('watchMessages emits an empty list when signed out', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: UidSource(
          currentUid: () => null,
          uidChanges: Stream.value(null),
        ),
      );

      final result = await repo.watchMessages('conv-1').first;
      expect(result, isEmpty);
    });

    test('send calls the injected invokeChat with the conversation id, '
        'trimmed text, and responseStyle (defaulting to balanced)', () async {
      final firestore = FakeFirebaseFirestore();
      final calls = <(String, String, String)>[];
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
        invokeChat: (conversationId, message, responseStyle) async {
          calls.add((conversationId, message, responseStyle));
        },
      );

      await repo.send(conversationId: 'conv-1', text: '  hello there  ');
      await repo.send(
        conversationId: 'conv-1',
        text: 'again',
        responseStyle: 'concise',
      );

      expect(calls, [
        ('conv-1', 'hello there', 'balanced'),
        ('conv-1', 'again', 'concise'),
      ]);
    });

    test('send is a no-op for empty or whitespace-only text', () async {
      final firestore = FakeFirebaseFirestore();
      var callCount = 0;
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
        invokeChat: (conversationId, message, responseStyle) async {
          callCount++;
        },
      );

      await repo.send(conversationId: 'conv-1', text: '');
      await repo.send(conversationId: 'conv-1', text: '   ');

      expect(callCount, 0);
    });

    test(
      "createConversation writes a fresh doc titled 'New chat', distinct "
      'from ensureConversation\'s default',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final id = await repo.createConversation();

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('aiConversations')
            .doc(id)
            .get();
        final data = doc.data()!;
        expect(data['title'], 'New chat');
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());
        expect(data['schemaVersion'], 1);
      },
    );

    test(
      'renameConversation updates only the title, leaving schemaVersion '
      'and timestamps untouched',
      () async {
        final firestore = FakeFirebaseFirestore();
        final doc = firestore
            .collection('users')
            .doc('test-uid')
            .collection('aiConversations')
            .doc('conv-1');
        final createdAt = Timestamp.fromDate(DateTime(2026, 1, 1));
        await doc.set({
          'title': 'New chat',
          'createdAt': createdAt,
          'updatedAt': createdAt,
          'schemaVersion': 1,
        });
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.renameConversation('conv-1', 'Trip planning');

        final data = (await doc.get()).data()!;
        expect(data['title'], 'Trip planning');
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], createdAt);
      },
    );

    test(
      'watchConversations emits docs newest-updatedAt first, uid-scoped',
      () async {
        final firestore = FakeFirebaseFirestore();
        final conversations = firestore
            .collection('users')
            .doc('test-uid')
            .collection('aiConversations');
        await conversations.doc('older').set({
          'title': 'Older chat',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'schemaVersion': 1,
        });
        await conversations.doc('newer').set({
          'title': 'Newer chat',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'schemaVersion': 1,
        });

        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final result = await repo.watchConversations().first;
        expect(result.map((c) => c.id).toList(), ['newer', 'older']);
      },
    );

    test('watchConversations emits an empty list when signed out', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: UidSource(
          currentUid: () => null,
          uidChanges: Stream.value(null),
        ),
      );

      final result = await repo.watchConversations().first;
      expect(result, isEmpty);
    });

    test(
      'latestConversation is a one-shot query for the newest-updatedAt doc '
      '(regression: AskPage used to resolve its initial conversation via '
      "watchConversations().first, whose FIRST emission can race Firestore's "
      'cache-then-server delivery and wrongly resolve to "no conversations")',
      () async {
        final firestore = FakeFirebaseFirestore();
        final conversations = firestore
            .collection('users')
            .doc('test-uid')
            .collection('aiConversations');
        await conversations.doc('older').set({
          'title': 'Older chat',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'schemaVersion': 1,
        });
        await conversations.doc('newer').set({
          'title': 'Newer chat',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
          'schemaVersion': 1,
        });

        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final latest = await repo.latestConversation();
        expect(latest?.id, 'newer');
        expect(latest?.title, 'Newer chat');
      },
    );

    test('latestConversation returns null when there are no conversations, '
        'or when signed out', () async {
      final firestore = FakeFirebaseFirestore();
      expect(
        await FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        ).latestConversation(),
        isNull,
      );
      expect(
        await FirebaseAiRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        ).latestConversation(),
        isNull,
      );
    });

    test(
      'deleteConversation calls the injected invokeDelete with the '
      'conversation id',
      () async {
        final firestore = FakeFirebaseFirestore();
        final calls = <String>[];
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
          invokeDelete: (conversationId) async {
            calls.add(conversationId);
          },
        );

        await repo.deleteConversation('conv-1');

        expect(calls, ['conv-1']);
      },
    );

    test("getResponseStyle defaults to 'balanced' when unset", () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      expect(await repo.getResponseStyle(), 'balanced');
    });

    test("getResponseStyle reads back a saved value, and ignores garbage",
        () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.setResponseStyle('detailed');
      expect(await repo.getResponseStyle(), 'detailed');

      await firestore
          .collection('users')
          .doc('test-uid')
          .collection('settings')
          .doc('ai')
          .set({'responseStyle': 'nonsense'});
      expect(await repo.getResponseStyle(), 'balanced');
    });

    test('setResponseStyle writes to users/{uid}/settings/ai without '
        'clobbering other fields there', () async {
      final firestore = FakeFirebaseFirestore();
      final doc = firestore
          .collection('users')
          .doc('test-uid')
          .collection('settings')
          .doc('ai');
      await doc.set({'unrelatedField': 'keep-me'});
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.setResponseStyle('concise');

      final data = (await doc.get()).data()!;
      expect(data['responseStyle'], 'concise');
      expect(data['unrelatedField'], 'keep-me');
    });

    test(
      'confirmAction / cancelAction call the matching callable with the ids',
      () async {
        final firestore = FakeFirebaseFirestore();
        final calls = <(String, String, String)>[];
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
          invokeAction: (name, conversationId, actionId) async {
            calls.add((name, conversationId, actionId));
          },
        );

        await repo.confirmAction(conversationId: 'conv-1', actionId: 'a1');
        await repo.cancelAction(conversationId: 'conv-1', actionId: 'a2');

        expect(calls, [
          ('aiConfirmAction', 'conv-1', 'a1'),
          ('aiCancelAction', 'conv-1', 'a2'),
        ]);
      },
    );

    test(
      'watchMessages maps an action_proposal doc to a pendingAction',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore
            .collection('users')
            .doc('test-uid')
            .collection('aiConversations')
            .doc('conv-1')
            .collection('messages')
            .doc('m1')
            .set({
              'role': 'assistant',
              'content': 'Add task "Submit report"',
              'kind': 'action_proposal',
              'actionId': 'act-1',
              'actionKind': 'create_task',
              'fields': {'title': 'Submit report', 'priority': 'High'},
              'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0)),
              'schemaVersion': 1,
            });

        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final result = await repo.watchMessages('conv-1').first;
        expect(result, hasLength(1));
        final action = result.single.pendingAction;
        expect(action, isNotNull);
        expect(action!.actionId, 'act-1');
        expect(action.kind, 'create_task');
        expect(action.fields['title'], 'Submit report');
        expect(action.isPending, isTrue);
      },
    );

    test('an action_proposal maps its stored status, so a resolved card stays '
        'resolved on reopen (regression: card reverted to pending)', () async {
      final firestore = FakeFirebaseFirestore();
      final messages = firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .doc('conv-1')
          .collection('messages');
      // A proposal the server has since marked applied (e.g. confirmed by a
      // typed reply rather than a card tap). On reopen the client must render
      // it as resolved, not pending — the bug hardcoded pending here.
      await messages.doc('m1').set({
        'role': 'assistant',
        'content': 'Add task "Submit report"',
        'kind': 'action_proposal',
        'actionId': 'act-1',
        'actionKind': 'create_task',
        'fields': {'title': 'Submit report'},
        'status': 'applied',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0)),
        'schemaVersion': 1,
      });

      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final action =
          (await repo.watchMessages('conv-1').first).single.pendingAction;
      expect(action, isNotNull);
      expect(action!.status, AiActionStatus.applied);
      expect(action.isPending, isFalse);
    });

    test('a still-pending proposal past its expiresAt renders as expired '
        '(regression: stale card offered Confirm until tapped)', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('users')
          .doc('test-uid')
          .collection('aiConversations')
          .doc('conv-1')
          .collection('messages')
          .doc('m1')
          .set({
            'role': 'assistant',
            'content': 'Add task "Submit report"',
            'kind': 'action_proposal',
            'actionId': 'act-1',
            'actionKind': 'create_task',
            'fields': {'title': 'Submit report'},
            'status': 'pending',
            // TTL already passed; never confirmed/cancelled, so status is
            // still 'pending' on the doc.
            'expiresAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 2)),
            ),
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 3)),
            ),
            'schemaVersion': 1,
          });

      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final action =
          (await repo.watchMessages('conv-1').first).single.pendingAction;
      expect(action, isNotNull);
      expect(action!.status, AiActionStatus.expired);
      expect(action.isPending, isFalse);
    });
  });

  group('FirebaseAiRepository.transcribe', () {
    test('calls the injected invokeTranscribe with the audio bytes, mime type, '
        'and languageHint, and returns its outcome unchanged', () async {
      final firestore = FakeFirebaseFirestore();
      final calls = <(Uint8List, String, String?)>[];
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
        invokeTranscribe: (audioBytes, mimeType, languageHint) async {
          calls.add((audioBytes, mimeType, languageHint));
          return const SttTranscribed(
            text: 'Hello there',
            detectedLanguage: 'en',
          );
        },
      );

      final bytes = Uint8List.fromList([1, 2, 3]);
      final outcome = await repo.transcribe(
        audioBytes: bytes,
        mimeType: 'audio/m4a',
        languageHint: 'en',
      );

      expect(calls, [(bytes, 'audio/m4a', 'en')]);
      expect(outcome, isA<SttTranscribed>());
      expect((outcome as SttTranscribed).text, 'Hello there');
      expect(outcome.detectedLanguage, 'en');
    });

    test(
      'omitting languageHint passes null through to invokeTranscribe',
      () async {
        final firestore = FakeFirebaseFirestore();
        String? seenLanguageHint = 'unset';
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
          invokeTranscribe: (audioBytes, mimeType, languageHint) async {
            seenLanguageHint = languageHint;
            return const SttTranscribed(text: 'hi');
          },
        );

        await repo.transcribe(
          audioBytes: Uint8List.fromList([1]),
          mimeType: 'audio/m4a',
        );

        expect(seenLanguageHint, isNull);
      },
    );

    test('returns SttFailed unchanged when the injected seam resolves to a '
        'failure (no exception is thrown)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
        invokeTranscribe: (audioBytes, mimeType, languageHint) async {
          return const SttFailed(
            SttError.audioTooLarge,
            'That recording is too long — try a shorter clip.',
          );
        },
      );

      final outcome = await repo.transcribe(
        audioBytes: Uint8List.fromList([1]),
        mimeType: 'audio/m4a',
      );

      expect(outcome, isA<SttFailed>());
      expect((outcome as SttFailed).error, SttError.audioTooLarge);
      expect(
        outcome.message,
        'That recording is too long — try a shorter clip.',
      );
    });
  });

  // The real `aiChat`/`aiTranscribe` callable invocations (the default
  // `invokeChat`/`invokeTranscribe`, calling
  // `FirebaseFunctions.instanceFor(region: 'us-central1')`) are exercised
  // on-device only — they need a live Cloud Functions deployment and cannot
  // be unit-tested here.
}
