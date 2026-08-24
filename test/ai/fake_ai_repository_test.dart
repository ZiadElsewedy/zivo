import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';

void main() {
  group('FakeAiRepository', () {
    test('ensureConversation returns a stable id', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      final id = await repo.ensureConversation();
      expect(id, isNotEmpty);
      expect(await repo.ensureConversation(), id);
    });

    test(
      'send appends a user message then the honest canned assistant reply',
      () async {
        final repo = FakeAiRepository();
        addTearDown(repo.dispose);
        final id = await repo.ensureConversation();

        await repo.send(conversationId: id, text: 'What is due this week?');

        final messages = await repo.watchMessages(id).first;
        expect(messages, hasLength(2));
        expect(messages[0].role, AiRole.user);
        expect(messages[0].content, 'What is due this week?');
        expect(messages[1].role, AiRole.assistant);
        expect(messages[1].content, kFakeAiReply);
        expect(messages[1].createdAt.isAfter(messages[0].createdAt), isTrue);
      },
    );

    test('empty or whitespace-only text is a no-op', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);
      final id = await repo.ensureConversation();

      await repo.send(conversationId: id, text: '   ');

      final messages = await repo.watchMessages(id).first;
      expect(messages, isEmpty);
    });

    test('transcribe returns a canned transcript by default', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      final outcome = await repo.transcribe(
        audioBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/m4a',
      );

      expect(outcome, isA<SttTranscribed>());
      expect((outcome as SttTranscribed).text, isNotEmpty);
    });

    test('transcribe delegates to an injected transcribeImpl', () async {
      final repo = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) async =>
            const SttTranscribed(text: 'scripted transcript'),
      );
      addTearDown(repo.dispose);

      final outcome = await repo.transcribe(
        audioBytes: Uint8List.fromList([1]),
        mimeType: 'audio/wav',
      );

      expect((outcome as SttTranscribed).text, 'scripted transcript');
    });

    test(
      'createConversation makes a fresh, separately-addressable conversation '
      "titled 'New chat'",
      () async {
        final repo = FakeAiRepository();
        addTearDown(repo.dispose);

        final id = await repo.createConversation();

        final conversations = await repo.watchConversations().first;
        expect(conversations, hasLength(1));
        expect(conversations.single.id, id);
        expect(conversations.single.title, 'New chat');
        expect(await repo.watchMessages(id).first, isEmpty);
      },
    );

    test(
      'watchConversations lists newest-updatedAt first and reflects a send',
      () async {
        final repo = FakeAiRepository();
        addTearDown(repo.dispose);

        final first = await repo.createConversation();
        final second = await repo.createConversation();
        // Sending in the older conversation bumps its updatedAt, so it sorts
        // back to the top.
        await repo.send(conversationId: first, text: 'hello');

        final conversations = await repo.watchConversations().first;
        expect(conversations.map((c) => c.id).toList(), [first, second]);
      },
    );

    test('latestConversation returns the most-recently-updated one, or null '
        'when there are none', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      expect(await repo.latestConversation(), isNull);

      final first = await repo.createConversation();
      final second = await repo.createConversation();
      expect((await repo.latestConversation())!.id, second);

      // Sending in the older conversation bumps its updatedAt, so it becomes
      // the latest again.
      await repo.send(conversationId: first, text: 'hello');
      expect((await repo.latestConversation())!.id, first);
    });

    test('renameConversation updates the title in watchConversations', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);
      final id = await repo.createConversation();

      await repo.renameConversation(id, 'Trip planning');

      final conversations = await repo.watchConversations().first;
      expect(conversations.single.title, 'Trip planning');
    });

    test(
      'deleteConversation removes it from the list and clears its messages',
      () async {
        final repo = FakeAiRepository();
        addTearDown(repo.dispose);
        final id = await repo.createConversation();
        await repo.send(conversationId: id, text: 'hello');

        await repo.deleteConversation(id);

        expect(await repo.watchConversations().first, isEmpty);
        expect(await repo.watchMessages(id).first, isEmpty);
      },
    );

    test("getResponseStyle defaults to 'balanced'", () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      expect(await repo.getResponseStyle(), 'balanced');
    });

    test('setResponseStyle persists a valid style; an invalid one falls '
        "back to 'balanced'", () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      await repo.setResponseStyle('concise');
      expect(await repo.getResponseStyle(), 'concise');

      await repo.setResponseStyle('nonsense');
      expect(await repo.getResponseStyle(), 'balanced');
    });
  });
}
