import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';

void main() {
  group('aiRoleFromName', () {
    test('round-trips known names', () {
      expect(aiRoleFromName('user'), AiRole.user);
      expect(aiRoleFromName('assistant'), AiRole.assistant);
      expect(aiRoleFromName('tool'), AiRole.tool);
    });

    test('falls back safely for unknown/null values', () {
      expect(aiRoleFromName('mystery'), AiRole.assistant);
      expect(aiRoleFromName(null), AiRole.assistant);
    });
  });

  group('AiMessage', () {
    test('holds the given fields', () {
      final createdAt = DateTime(2026, 1, 1);
      final message = AiMessage(
        id: 'm1',
        role: AiRole.user,
        content: 'Hello',
        createdAt: createdAt,
      );

      expect(message.id, 'm1');
      expect(message.role, AiRole.user);
      expect(message.content, 'Hello');
      expect(message.createdAt, createdAt);
    });
  });

  group('AiConversation', () {
    test('holds the given fields', () {
      final createdAt = DateTime(2026, 1, 1);
      final updatedAt = DateTime(2026, 1, 2);
      final conversation = AiConversation(
        id: 'c1',
        title: 'Chat',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(conversation.id, 'c1');
      expect(conversation.title, 'Chat');
      expect(conversation.createdAt, createdAt);
      expect(conversation.updatedAt, updatedAt);
    });
  });
}
