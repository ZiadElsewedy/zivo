import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
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

  group('the untitled-conversation sentinel', () {
    test('is a stable stored value, never a translated string', () {
      // If this ever becomes localized, every `title == kUntitledConversationTitle`
      // comparison silently breaks the moment the user switches language, and
      // threads created in one language read as "titled" in another.
      expect(kUntitledConversationTitle, 'New chat');
    });

    testWidgets('a thread still holding the sentinel is DISPLAYED in Arabic', (tester) async {
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
      expect(displayConversationTitle(ctx, 'Bench press plan'), 'Bench press plan');
      expect(displayConversationTitle(ctx, 'خطة الضغط'), 'خطة الضغط');
    });

    testWidgets('a new conversation is still STORED as the English sentinel', (tester) async {
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
