import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/error_retry.dart';

Widget _card(AiFailure failure, {VoidCallback? onSwitch}) => MaterialApp(
  home: Scaffold(
    body: ErrorRetry(failure: failure, onRetry: () {}, onSwitchModel: onSwitch),
  ),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('a provider failure names the provider and the reason, and '
      'offers Switch model', (tester) async {
    var switched = false;
    await tester.pumpWidget(
      _card(
        const AiFailure(
          AiFailureKind.unavailable,
          provider: 'anthropic',
          issue: AiProviderIssue.outOfCredit,
        ),
        onSwitch: () => switched = true,
      ),
    );

    expect(_text(tester, 'error-retry-title'), "Claude isn't available");
    expect(_text(tester, 'error-retry-body'), contains('out of credit'));
    // "Usage limit" is ZIVO's own daily Ask cap — a provider's billing
    // problem must never read like it.
    expect(_text(tester, 'error-retry-body'), isNot(contains('usage limit')));
    await tester.tap(find.byKey(const Key('error-switch-model')));
    expect(switched, isTrue);
  });

  testWidgets('a slow model says it didn\'t respond — no Switch button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(
        const AiFailure(
          AiFailureKind.unavailable,
          provider: 'gemini',
          issue: AiProviderIssue.noResponse,
        ),
        onSwitch: () {},
      ),
    );
    expect(_text(tester, 'error-retry-title'), "Gemini didn't respond");
    expect(find.byKey(const Key('error-switch-model')), findsNothing);
  });

  testWidgets('a dropped connection is not blamed on the model', (
    tester,
  ) async {
    await tester.pumpWidget(_card(const AiFailure(AiFailureKind.network)));
    expect(_text(tester, 'error-retry-title'), "Couldn't reach ZIVO");
    expect(find.byKey(const Key('error-retry-button')), findsOneWidget);
  });
}
