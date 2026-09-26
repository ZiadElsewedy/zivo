import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/bidi.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/presentation/assistant_text.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/message_bubble.dart';

/// The display pass every coach reply goes through (`assistant_text.dart`):
/// direction from the dominant script, Latin/number runs isolated inside
/// Arabic, stray Markdown removed.
void main() {
  group('direction is the language MOST of the reply is in', () {
    test('an Arabic reply that opens with an English name is still RTL', () {
      final shown = assistantDisplay(
        'Pull النهارده مناسب ليك، آخر تمرين كان من يومين ونومك كويس.',
        fallback: TextDirection.ltr,
      );
      expect(shown.direction, TextDirection.rtl);
    });

    test('an English reply with one Arabic word stays LTR, untouched', () {
      const reply = 'Yes — train today. Keep it moderate (خفيف).';
      final shown = assistantDisplay(reply, fallback: TextDirection.rtl);
      expect(shown.direction, TextDirection.ltr);
      expect(shown.text, reply, reason: 'no isolates under LTR');
    });

    test('the live bubble takes its direction from everything streamed, so '
        'a half-written opening word cannot flip it', () {
      final shown = assistantDisplay(
        'Pull',
        fallback: TextDirection.ltr,
        directionSource: 'Pull النهارده مناسب ليك جدًا',
      );
      expect(shown.direction, TextDirection.rtl);
    });
  });

  group('inside Arabic, Latin and number runs are pinned LTR', () {
    test('a rep range can no longer read backwards', () {
      final shown = assistantDisplay(
        'اعمل 3 مجموعات من 8–10 عدات',
        fallback: TextDirection.rtl,
      );
      expect(shown.text, contains(ltr('8–10')));
      expect(stripBidi(shown.text), 'اعمل 3 مجموعات من 8–10 عدات');
    });

    test('an exercise spec stays one piece; sentence punctuation stays out',
        () {
      final shown = assistantDisplay(
        'ابدأ بـ Bench Press 3×8، وبعدها Pull-ups.',
        fallback: TextDirection.rtl,
      );
      expect(shown.text, contains(ltr('Bench Press 3×8')));
      expect(shown.text, contains('${ltr('Pull-ups')}.'));
    });
  });

  group('stray Markdown is cleaned, plain text passes through', () {
    test('bold, headings and dash bullets become plain text and "• "', () {
      expect(
        cleanAssistantText('## الخطة\n**اتمرن** النهارده\n- Pull\n* نوم كويس'),
        'الخطة\nاتمرن النهارده\n• Pull\n• نوم كويس',
      );
    });

    test('paragraph spacing evens out to one blank line', () {
      expect(
        cleanAssistantText('أيوه، اتمرن.  \n\n\n\nخففها شوية.'),
        'أيوه، اتمرن.\n\nخففها شوية.',
      );
    });

    test('plain replies are untouched', () {
      const reply = 'Yes — train today.\n\n• Pull is up next\n• 5 × 3 at 80 kg';
      expect(cleanAssistantText(reply), reply);
    });
  });

  testWidgets('the bubble lays an Arabic reply that opens with "Pull" out '
      'right-to-left, even in an English app', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MessageBubble(
            AiMessage(
              id: 'm1',
              role: AiRole.assistant,
              content: 'Pull النهارده مناسب ليك، من 8–10 عدات.',
              createdAt: DateTime(2026, 9, 26),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text).last);
    expect(text.textDirection, TextDirection.rtl);
    expect(text.data, contains(ltr('8–10')));
  });
}
