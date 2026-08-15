import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';

void main() {
  group('FakeAiRepository', () {
    test('ensureConversation returns a stable id', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);

      final id = await repo.ensureConversation();
      expect(id, isNotEmpty);
      expect(await repo.ensureConversation(), id);
    });

    test('send appends a user message then the honest canned assistant reply', () async {
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
    });

    test('empty or whitespace-only text is a no-op', () async {
      final repo = FakeAiRepository();
      addTearDown(repo.dispose);
      final id = await repo.ensureConversation();

      await repo.send(conversationId: id, text: '   ');

      final messages = await repo.watchMessages(id).first;
      expect(messages, isEmpty);
    });
  });
}
