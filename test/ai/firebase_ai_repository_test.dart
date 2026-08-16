import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/ai/data/firebase_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

void main() {
  group('FirebaseAiRepository', () {
    test(
      'ensureConversation creates a conversation doc when none exists, '
      'and reuses it on a second call',
      () async {
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
      },
    );

    test(
      'ensureConversation reuses an existing conversation found in '
      'Firestore (not just the in-memory cache)',
      () async {
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
      },
    );

    test(
      'watchMessages maps seeded message docs to AiMessages in createdAt '
      'order with correct roles',
      () async {
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
      },
    );

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

    test(
      'send calls the injected invokeChat with the conversation id and '
      'trimmed text',
      () async {
        final firestore = FakeFirebaseFirestore();
        final calls = <(String, String)>[];
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
          invokeChat: (conversationId, message) async {
            calls.add((conversationId, message));
          },
        );

        await repo.send(conversationId: 'conv-1', text: '  hello there  ');

        expect(calls, [('conv-1', 'hello there')]);
      },
    );

    test('send is a no-op for empty or whitespace-only text', () async {
      final firestore = FakeFirebaseFirestore();
      var callCount = 0;
      final repo = FirebaseAiRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
        invokeChat: (conversationId, message) async {
          callCount++;
        },
      );

      await repo.send(conversationId: 'conv-1', text: '');
      await repo.send(conversationId: 'conv-1', text: '   ');

      expect(callCount, 0);
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

    test('watchMessages maps an action_proposal doc to a pendingAction', () async {
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
    });
  });

  // The real `aiChat` callable invocation (the default `invokeChat`, calling
  // `FirebaseFunctions.instanceFor(region: 'us-central1')`) is exercised
  // on-device only — it needs a live Cloud Functions deployment and cannot
  // be unit-tested here.
}
