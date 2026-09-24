import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/data/firebase_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_choice_request.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/choice_card.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// The Ask choice system, client half: the `choice_request` contract the
/// gateway writes (`functions/ai/chat/choices.js`), the native card that
/// renders it, and the tap that answers it with a structured
/// [AiChoiceSelection] rather than text.
void main() {
  group('choice_request contract (FirebaseAiRepository)', () {
    CollectionReference<Map<String, dynamic>> messagesOf(
      FakeFirebaseFirestore f,
    ) => f
        .collection('users')
        .doc('u')
        .collection('aiConversations')
        .doc('c')
        .collection('messages');

    FirebaseAiRepository repoOn(
      FakeFirebaseFirestore f, {
      void Function(AiChoiceSelection?)? onChat,
    }) => FirebaseAiRepository(
      firestore: f,
      uidSource: UidSource(
        currentUid: () => 'u',
        uidChanges: Stream.value('u'),
      ),
      invokeChat: (cid, message, style, provider, turnId, choice) async =>
          onChat?.call(choice),
    );

    test('a card maps to structured options with their verified figures, '
        'and an answered card carries its pick', () async {
      final f = FakeFirebaseFirestore();
      await messagesOf(f).doc('m1').set({
        'role': 'assistant',
        'kind': 'choice_request',
        'content': 'Which one would you like?',
        'requestId': 'req-1',
        'status': 'answered',
        'selectedValue': 'usda:175160',
        'fields': {
          'options': [
            {
              'value': 'usda:173420',
              'label': 'Feta cheese',
              'subtitle': '90 g · 239 kcal · 12.8 g protein',
              'metadata': {'grams': 90, 'kcal': 239, 'proteinG': 12.8},
            },
            {'value': 'usda:175160', 'label': 'Tuna salad'},
          ],
          'allowMultiple': false,
        },
        // Server-only resolution: never parsed into the client model.
        'bindings': {
          'usda:173420': {'tool': 'replace_meal_item'},
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 24)),
      });

      final [message] = await repoOn(f).watchMessages('c').first;
      final card = message.choiceRequest!;
      expect(card.requestId, 'req-1');
      expect(card.options.map((o) => o.value), ['usda:173420', 'usda:175160']);
      expect(card.options.first.metadata, {
        'grams': 90,
        'kcal': 239,
        'proteinG': 12.8,
      });
      expect(card.selectedValue, 'usda:175160');
    });

    test('an open card has no pick; a card with fewer than two options is '
        'no card at all', () async {
      final f = FakeFirebaseFirestore();
      await messagesOf(f).doc('m1').set({
        'role': 'assistant',
        'kind': 'choice_request',
        'content': 'Pick one',
        'requestId': 'req-open',
        'status': 'pending',
        'fields': {
          'options': [
            {'value': 'a', 'label': 'A'},
            {'value': 'b', 'label': 'B'},
          ],
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 24, 1)),
      });
      await messagesOf(f).doc('m2').set({
        'role': 'assistant',
        'kind': 'choice_request',
        'content': 'I found nothing I could price.',
        'requestId': 'req-empty',
        'fields': {
          'options': [
            {'value': 'a', 'label': 'A'},
          ],
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 24, 2)),
      });

      final [open, empty] = await repoOn(f).watchMessages('c').first;
      expect(open.choiceRequest!.selectedValue, isNull);
      expect(empty.choiceRequest, isNull);
      expect(empty.content, 'I found nothing I could price.');
    });

    test('send forwards the structured pick to the gateway', () async {
      AiChoiceSelection? sent;
      final repo = repoOn(
        FakeFirebaseFirestore(),
        onChat: (choice) => sent = choice,
      );
      await repo.send(
        conversationId: 'c',
        text: 'Tuna salad',
        choice: const AiChoiceSelection(
          requestId: 'req-1',
          value: 'usda:175160',
        ),
      );
      expect(sent!.requestId, 'req-1');
      expect(sent!.value, 'usda:175160');
    });
  });

  group('ChoiceCard', () {
    const request = AiChoiceRequest(
      requestId: 'req-1',
      prompt: 'I found 3 verified swaps. Which one would you like?',
      options: _eggSwaps,
    );

    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('renders real tappable rows with the verified figures — not '
        'Markdown or numbered text', (tester) async {
      final taps = <(String, String)>[];
      await tester.pumpWidget(
        host(
          ChoiceCard(
            request: request,
            pickedValue: null,
            onSelect: (v, label) => taps.add((v, label)),
          ),
        ),
      );

      for (final o in _eggSwaps) {
        expect(find.byKey(ValueKey('choice-option-${o.value}')), findsOne);
      }
      expect(
        find.descendant(
          of: find.byType(ChoiceCard),
          matching: find.byType(InkWell),
        ),
        findsNWidgets(3),
      );
      expect(find.text('90 g · 239 kcal · 12.8 g protein'), findsOneWidget);
      expect(find.text('130 g · 243 kcal · 20.8 g protein'), findsOneWidget);
      expect(find.textContaining('- Feta'), findsNothing);
      expect(find.textContaining('1.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('choice-option-usda:175160')));
      expect(taps, [('usda:175160', 'Tuna salad')]);
    });

    testWidgets('an answered card marks its pick and takes no more taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          ChoiceCard(
            request: request,
            pickedValue: 'usda:171501',
            onSelect: (_, _) => taps++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('choice-option-usda:173420')));
      await tester.tap(find.byKey(const ValueKey('choice-option-usda:171501')));
      expect(taps, 0);

      final picked = tester.getSemantics(
        find.byKey(const ValueKey('choice-option-usda:171501')),
      );
      expect(picked.flagsCollection.isSelected, Tristate.isTrue);
      expect(picked.label, contains('Turkey breast'));
    });
  });

  group('tapping a choice in Ask', () {
    Future<(FakeAiRepository, String, String)> seeded() async {
      final ai = FakeAiRepository();
      final cid = await ai.createConversation();
      await ai.send(conversationId: cid, text: "I don't want egg");
      final requestId = ai.askChoice(
        conversationId: cid,
        prompt: 'I found 3 verified swaps. Which one would you like?',
        options: _eggSwaps,
      );
      return (ai, cid, requestId);
    }

    testWidgets('resolves the tapped option by id, shows it as the user\'s '
        'message, and settles the card', (tester) async {
      final (ai, cid, requestId) = await seeded();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('choice-option-usda:175160')));
      await tester.pumpAndSettle();

      expect(ai.lastChoice!.requestId, requestId);
      expect(ai.lastChoice!.value, 'usda:175160');
      final thread = await ai.watchMessages(cid).first;
      final user = thread.lastWhere((m) => m.role == AiRole.user);
      expect(user.content, 'Tuna salad');
      final card = thread
          .firstWhere((m) => m.choiceRequest != null)
          .choiceRequest!;
      expect(card.selectedValue, 'usda:175160');

      // A second tap on the settled card sends nothing.
      final sentBefore = thread.length;
      await tester.tap(find.byKey(const ValueKey('choice-option-usda:173420')));
      await tester.pumpAndSettle();
      expect((await ai.watchMessages(cid).first).length, sentBefore);
    });

    testWidgets('different questions in one thread answer through the same '
        'system, each by its own id', (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      final cid = await ai.createConversation();
      await ai.send(conversationId: cid, text: 'help me set up this week');
      final plan = ai.askChoice(
        conversationId: cid,
        prompt: 'Which plan do you want?',
        options: const [
          AiChoiceOption(value: 'plan-cut', label: 'Cut'),
          AiChoiceOption(value: 'plan-maintain', label: 'Maintain'),
        ],
      );
      final style = ai.askChoice(
        conversationId: cid,
        prompt: 'Which version?',
        options: const [
          AiChoiceOption(value: 'recommended', label: 'Recommended'),
          AiChoiceOption(value: 'higher-protein', label: 'Higher protein'),
          AiChoiceOption(value: 'lower-calorie', label: 'Lower calorie'),
        ],
      );
      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceCard), findsNWidgets(2));

      await _tapOption(tester, 'plan-cut');
      expect(ai.lastChoice!.requestId, plan);
      expect(ai.lastChoice!.value, 'plan-cut');

      await _tapOption(tester, 'higher-protein');
      expect(ai.lastChoice!.requestId, style);
      expect(ai.lastChoice!.value, 'higher-protein');
    });

    test('a stale or unknown pick is rejected, not applied', () async {
      final (ai, cid, requestId) = await seeded();
      addTearDown(ai.dispose);
      Future<void> pick(String req, String value) => ai.send(
        conversationId: cid,
        text: 'x',
        choice: AiChoiceSelection(requestId: req, value: value),
      );

      await expectLater(pick(requestId, 'usda:0'), throwsA(isA<AiFailure>()));
      await expectLater(
        pick('no-card', 'usda:173420'),
        throwsA(isA<AiFailure>()),
      );
      await pick(requestId, 'usda:173420');
      await expectLater(
        pick(requestId, 'usda:175160'),
        throwsA(isA<AiFailure>()),
        reason: 'an answered card stays answered once',
      );
    });

    testWidgets('no verified options → no choice widgets', (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      final cid = await ai.createConversation();
      await ai.send(conversationId: cid, text: "I don't want egg");
      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceCard), findsNothing);
    });
  });
}

/// Taps an option row after centring it — the thread's glass header floats
/// over the top of the list, so a row scrolled flush to the top is covered.
Future<void> _tapOption(WidgetTester tester, String value) async {
  final row = find.byKey(ValueKey('choice-option-$value'));
  await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

const _eggSwaps = [
  AiChoiceOption(
    value: 'usda:173420',
    label: 'Feta cheese',
    subtitle: '90 g · 239 kcal · 12.8 g protein',
    metadata: {'grams': 90, 'kcal': 239, 'proteinG': 12.8},
  ),
  AiChoiceOption(
    value: 'usda:175160',
    label: 'Tuna salad',
    subtitle: '130 g · 243 kcal · 20.8 g protein',
    metadata: {'grams': 130, 'kcal': 243, 'proteinG': 20.8},
  ),
  AiChoiceOption(
    value: 'usda:171501',
    label: 'Turkey breast',
    subtitle: '190 g · 239 kcal · 42.2 g protein',
    metadata: {'grams': 190, 'kcal': 239, 'proteinG': 42.2},
  ),
];

Widget _host(FakeAiRepository ai) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  child: const MaterialApp(home: AskPage()),
);
