import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_choice_request.dart';
import 'package:zivo/features/ai/domain/ai_pending_action.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/choice_tray.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/proposal_card.dart';
import 'package:zivo/l10n/app_localizations.dart';

import '../support/bidi_finders.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  ),
);

AiPendingAction _workout(String mode, AiActionStatus status) => AiPendingAction(
  actionId: 'a1',
  kind: 'change_workout_day',
  summary: 'x',
  fields: {
    'mode': mode,
    'from': 'Push',
    'to': 'Pull',
    'then': mode == 'swap' ? 'Push' : 'Legs',
  },
  status: status,
);

void main() {
  testWidgets('a swap reads as the day you train today, what it replaces, '
      'and what comes next', (tester) async {
    await tester.pumpWidget(
      _host(
        ProposalCard(
          action: _workout('swap', AiActionStatus.pending),
          status: AiActionStatus.pending,
          onConfirm: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('Workout swap'), findsOneWidget);
    expect(findTextIgnoringBidi('Pull today'), findsOneWidget);
    expect(find.text('Instead of'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.byKey(const Key('proposal-confirm')), findsOneWidget);
  });

  testWidgets('a skip says the skipped day comes back next round; once '
      'confirmed the decision folds into the outcome', (tester) async {
    await tester.pumpWidget(
      _host(
        ProposalCard(
          action: _workout('skip', AiActionStatus.applied),
          status: AiActionStatus.applied,
          onConfirm: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('Skip workout'), findsOneWidget);
    expect(findTextIgnoringBidi('Push, back next round'), findsOneWidget);
    expect(find.text('Then'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byKey(const Key('proposal-confirm')), findsNothing);
  });

  testWidgets('short answers flow in a row; skip / swap explain themselves in '
      'the reader\'s words', (tester) async {
    await tester.pumpWidget(
      _host(
        ChoiceTray(
          request: const AiChoiceRequest(
            requestId: 'r',
            prompt: 'What category?',
            options: [
              AiChoiceOption(value: 'food', label: 'Food'),
              AiChoiceOption(value: 'coffee', label: 'Coffee'),
              AiChoiceOption(value: 'transport', label: 'Transport'),
            ],
          ),
          onSelect: (_, _) {},
        ),
      ),
    );
    final food = tester.getTopLeft(findTextIgnoringBidi('Food'));
    final coffee = tester.getTopLeft(findTextIgnoringBidi('Coffee'));
    expect(food.dy, coffee.dy, reason: 'one row, not a stack');

    await tester.pumpWidget(
      _host(
        ChoiceTray(
          request: const AiChoiceRequest(
            requestId: 'r2',
            prompt: 'Skip or swap?',
            options: [
              AiChoiceOption(
                value: 'skip',
                label: 'Skip Push',
                metadata: {'mode': 'skip', 'from': 'Push', 'to': 'Pull'},
              ),
              AiChoiceOption(
                value: 'swap',
                label: 'Swap Push and Pull',
                metadata: {'mode': 'swap', 'from': 'Push', 'to': 'Pull'},
              ),
            ],
          ),
          onSelect: (_, _) {},
        ),
      ),
    );
    expect(
      findTextIgnoringBidi('Pull today, Push waits till next round'),
      findsOneWidget,
    );
    expect(findTextIgnoringBidi('Pull today, Push next'), findsOneWidget);
  });
}
