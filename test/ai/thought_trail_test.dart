import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/presentation/ai_thought.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/thought_trail.dart';
import 'package:zivo/l10n/app_localizations.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('working: finished steps read as what ZIVO did, the head as '
      'what it is doing — in words, never tool names', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThoughtTrail(
          steps: [
            AiActivityStep('get_diet', AiStepStatus.ok),
            AiActivityStep('search_food_alternatives', AiStepStatus.running),
          ],
          live: LiveThought(
            kind: AiThoughtKind.suggesting,
            label: 'Suggesting alternatives…',
          ),
        ),
        reduceMotion: true,
      ),
    );
    expect(find.textContaining('Read your meal plan'), findsOneWidget);
    expect(find.text('Suggesting alternatives…'), findsOneWidget);
    expect(find.textContaining('Grab'), findsNothing);
  });

  testWidgets('settled: one line of distinct verbs; an unknown tool is left '
      'out; a fallback is always said', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThoughtTrail(
          steps: [
            AiActivityStep.fallback('gemini-flash', 'claude-sonnet'),
            AiActivityStep('get_diet', AiStepStatus.ok),
            AiActivityStep('get_today', AiStepStatus.ok),
            AiActivityStep('get_readiness', AiStepStatus.ok),
            AiActivityStep('get_body_composition', AiStepStatus.ok),
          ],
        ),
        reduceMotion: true,
      ),
    );
    // Two reads collapse into one verb.
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Analyzed'), findsOneWidget);
    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(find.textContaining('body_composition'), findsNothing);

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read your meal plan'), findsOneWidget);
    expect(find.textContaining('Read your day'), findsOneWidget);
    expect(find.textContaining('Analyzed your readiness'), findsOneWidget);
  });

  test('every known tool has a human state; unknown ones think', () {
    for (final tool in [
      'get_today',
      'get_diet',
      'get_workouts',
      'get_last_workout',
      'get_training_analysis',
      'get_exercise_analysis',
      'get_expenses',
      'summarize_week',
      'get_readiness',
      'get_sleep_summary',
      'resolve_food',
      'calculate_meal_nutrition',
      'search_food_product',
      'search_food_alternatives',
    ]) {
      expect(aiThoughtKnowsTool(tool), isTrue, reason: tool);
      expect(aiThoughtKindForTool(tool), isNot(AiThoughtKind.thinking));
    }
    expect(aiThoughtKindForTool('get_new_thing'), AiThoughtKind.thinking);
    expect(aiThoughtKnowsTool('get_new_thing'), isFalse);
  });
}
