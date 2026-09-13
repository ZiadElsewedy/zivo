import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/core/theme/app_typography.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/message_bubble.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/sessions_sheet.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/l10n/l10n.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _host(FakeAiRepository ai, Locale locale, {Widget? child}) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child ?? const AskPage(),
  ),
);

void main() {
  group('the Ask surface renders in Arabic', () {
    testWidgets('the empty state greets and prompts in Arabic', (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai, const Locale('ar')));
      await tester.pumpAndSettle();

      for (final english in const [
        "Hey, I'm ZIVO.",
        'What did I spend this week?',
        'How is my training going?',
        'Ask',
      ]) {
        expect(
          find.text(english),
          findsNothing,
          reason: '"$english" is still hardcoded English',
        );
      }
      expect(find.text('أهلًا، أنا ZIVO.'), findsOneWidget);
    });

    testWidgets('English is unchanged under Locale("en")', (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai, const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
      expect(find.text('What did I spend this week?'), findsOneWidget);
    });
  });

  group('a message reads in ITS OWN language, not the app\'s', () {
    // The bug this pins: an English reply under an Arabic UI inherited the
    // app's right-to-left paragraph. The words stayed in order — bidi keeps a
    // Latin run intact — but the block right-aligned and the closing full stop
    // was laid out at the paragraph's end, which under RTL is the LEFT edge:
    // ".answer using your real ZIVO data".
    testWidgets(
      'ZIVO answering in English stays left-to-right in an Arabic app',
      (tester) async {
        final ai = FakeAiRepository();
        addTearDown(ai.dispose);
        await tester.pumpWidget(_host(ai, const Locale('ar')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'كم أنفقت هذا الأسبوع؟');
        await tester.pump();
        await tester.tap(find.byKey(const Key('composer-send')));
        await tester.pumpAndSettle();

        final reply = tester.widget<Text>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.text(kFakeAiReply),
          ),
        );
        expect(reply.textDirection, TextDirection.ltr);
        expect(reply.textAlign, TextAlign.start);

        // The user's own Arabic question keeps its own direction in the same
        // thread — the two bubbles do not have to agree.
        final asked = tester.widget<Text>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.text('كم أنفقت هذا الأسبوع؟'),
          ),
        );
        expect(asked.textDirection, TextDirection.rtl);
      },
    );

    testWidgets(
      'the user typing Arabic into an English app reads right-to-left',
      (tester) async {
        final ai = FakeAiRepository();
        addTearDown(ai.dispose);
        await tester.pumpWidget(_host(ai, const Locale('en')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'كم أنفقت هذا الأسبوع؟');
        await tester.pump();
        await tester.tap(find.byKey(const Key('composer-send')));
        await tester.pumpAndSettle();

        final asked = tester.widget<Text>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.text('كم أنفقت هذا الأسبوع؟'),
          ),
        );
        expect(asked.textDirection, TextDirection.rtl);
      },
    );
  });

  group("ZIVO's voice in a script that has no italic", () {
    // Instrument Serif is Latin-only. Asking it for italic over Arabic gets no
    // Arabic italic — there is none — so the shaper slants the system's
    // upright fallback instead, and the greeting rendered as an obliqued
    // أهلًا. The serif stays; the slant does not.
    testWidgets('the greeting is upright in Arabic and italic in English', (
      tester,
    ) async {
      for (final (locale, expected) in const [
        (Locale('ar'), FontStyle.normal),
        (Locale('en'), FontStyle.italic),
      ]) {
        final ai = FakeAiRepository();
        addTearDown(ai.dispose);
        await tester.pumpWidget(_host(ai, locale));
        await tester.pumpAndSettle();

        final greeting = tester.widget<Text>(
          find.text(
            locale.languageCode == 'ar' ? 'أهلًا، أنا ZIVO.' : "Hey, I'm ZIVO.",
          ),
        );
        expect(
          greeting.style?.fontStyle,
          expected,
          reason: 'the voice face under ${locale.languageCode}',
        );
        // Same family either way — one reserved face, still only where ZIVO
        // speaks. Dropping the slant is not dropping the voice.
        expect(greeting.style?.fontFamily, contains('InstrumentSerif'));
      }
    });

    testWidgets('every aside on the ladder follows the same rule', (
      tester,
    ) async {
      late TextStyle rtl;
      late TextStyle ltr;
      await tester.pumpWidget(
        Column(
          textDirection: TextDirection.ltr,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (context) {
                  rtl = AppText.aside(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) {
                  ltr = TrainType.serifVoice(context, size: 21);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      );
      expect(rtl.fontStyle, FontStyle.normal);
      expect(ltr.fontStyle, FontStyle.italic);
    });
  });

  group('the Ask header speaks Arabic too', () {
    testWidgets('the settings page is translated, not English words', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai, const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header-settings')));
      await tester.pumpAndSettle();

      for (final english in const [
        'Concise',
        'Balanced',
        'Detailed',
        'Auto',
      ]) {
        expect(
          find.text(english),
          findsNothing,
          reason: '"$english" is still hardcoded English in the settings sheet',
        );
      }
      // Reply-style words, in Arabic.
      expect(find.text('موجز'), findsOneWidget);
      expect(find.text('متوازن'), findsOneWidget);
      expect(find.text('مفصّل'), findsOneWidget);
      // The model section's "Auto" word, in Arabic.
      expect(find.text('تلقائي'), findsOneWidget);
    });

    testWidgets('a chat\'s relative timestamp is translated', (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai, const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'مرحبًا');
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header-history')));
      await tester.pumpAndSettle();

      expect(find.text('now'), findsNothing);
      expect(find.text('الآن'), findsOneWidget);
    });
  });

  group('the untitled-conversation sentinel', () {
    test('is a stable stored value, never a translated string', () {
      // If this ever becomes localized, every `title == kUntitledConversationTitle`
      // comparison silently breaks the moment the user switches language, and
      // threads created in one language read as "titled" in another.
      expect(kUntitledConversationTitle, 'New chat');
    });

    testWidgets('a thread still holding the sentinel is DISPLAYED in Arabic', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The stored sentinel is translated at the render boundary…
      expect(
        displayConversationTitle(ctx, kUntitledConversationTitle),
        'محادثة جديدة',
      );
      // …while a thread the first message named keeps its own text verbatim,
      // in whatever language the user wrote it.
      expect(
        displayConversationTitle(ctx, 'Bench press plan'),
        'Bench press plan',
      );
      expect(displayConversationTitle(ctx, 'خطة الضغط'), 'خطة الضغط');
    });

    testWidgets('a new conversation is still STORED as the English sentinel', (
      tester,
    ) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai, const Locale('ar')));
      await tester.pumpAndSettle();

      final id = await ai.createConversation();
      final conversations = await ai.watchConversations().first;
      final created = conversations.firstWhere((c) => c.id == id);
      expect(
        created.title,
        kUntitledConversationTitle,
        reason: 'the persisted title must not depend on the UI locale',
      );
    });
  });
}
