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
  });
}
