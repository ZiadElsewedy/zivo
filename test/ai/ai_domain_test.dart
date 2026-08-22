import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/stt_error.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';

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

  group('SttOutcome', () {
    test(
      'SttTranscribed holds the given fields, with optional ones nullable',
      () {
        const full = SttTranscribed(
          text: 'Hello there',
          detectedLanguage: 'en',
          durationMs: 1500,
        );
        expect(full.text, 'Hello there');
        expect(full.detectedLanguage, 'en');
        expect(full.durationMs, 1500);

        const minimal = SttTranscribed(text: 'Hi');
        expect(minimal.text, 'Hi');
        expect(minimal.detectedLanguage, isNull);
        expect(minimal.durationMs, isNull);
      },
    );

    test('SttFailed holds the given error and message', () {
      const failed = SttFailed(SttError.audioTooLarge, 'Too long.');
      expect(failed.error, SttError.audioTooLarge);
      expect(failed.message, 'Too long.');
    });

    test('is a sealed type switchable without a default case', () {
      String describe(SttOutcome outcome) => switch (outcome) {
        SttTranscribed(:final text) => 'ok:$text',
        SttFailed(:final error) => 'failed:${error.name}',
      };

      expect(describe(const SttTranscribed(text: 'hi')), 'ok:hi');
      expect(
        describe(const SttFailed(SttError.timeout, 'Took too long.')),
        'failed:timeout',
      );
    });
  });
}
