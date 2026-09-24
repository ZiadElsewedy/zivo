import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/activity_timeline.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/message_bubble.dart';
import 'package:zivo/l10n/app_localizations.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('each tool reads as a human label, never its identifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ActivityTimeline([
          AiActivityStep('get_diet', AiStepStatus.ok),
          AiActivityStep('suggest_meal_replacement', AiStepStatus.running),
          AiActivityStep('get_workouts', AiStepStatus.error),
        ]),
      ),
    );

    expect(find.text('Grab · Diet details'), findsOneWidget);
    expect(find.text('Search · Food alternatives'), findsOneWidget);
    expect(find.text('Grab · Workout details'), findsOneWidget);
    expect(find.textContaining('get_'), findsNothing);
    expect(find.textContaining('suggest_'), findsNothing);
  });

  testWidgets('an unknown tool is left out rather than named', (tester) async {
    await tester.pumpWidget(
      _host(
        const ActivityTimeline([
          AiActivityStep('get_body_composition', AiStepStatus.ok),
        ]),
      ),
    );
    expect(find.textContaining('get_body_composition'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('labels are localized', (tester) async {
    await tester.pumpWidget(
      _host(
        const ActivityTimeline([AiActivityStep('get_diet', AiStepStatus.ok)]),
        locale: const Locale('ar'),
      ),
    );
    expect(find.text('جلب · تفاصيل النظام الغذائي'), findsOneWidget);
  });

  testWidgets('an assistant reply draws its persisted timeline above it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubble(
          AiMessage(
            id: 'm1',
            role: AiRole.assistant,
            content: 'I checked your diet and found the molokhia at lunch.',
            createdAt: DateTime(2026),
            activity: const [AiActivityStep('get_diet', AiStepStatus.ok)],
          ),
        ),
      ),
    );
    final chip = tester.getTopLeft(find.text('Grab · Diet details'));
    final reply = tester.getTopLeft(
      find.textContaining('I checked your diet'),
    );
    expect(chip.dy, lessThan(reply.dy));
  });
}
