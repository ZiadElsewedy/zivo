import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/firebase_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/ai/domain/ai_usage_summary.dart';
import 'package:zivo/features/ai/presentation/ai_labels.dart';
import 'package:zivo/l10n/app_localizations.dart';

/// ZIVO's own daily Ask limit and each provider failure are different states
/// and must read as different states.
void main() {
  usageMain();

  AiFailure providerFailure(String kind, String provider) =>
      aiFailureFrom(
            FirebaseFunctionsException(
              code: 'unavailable',
              message: 'x',
              details: {
                'reason': 'ai_unavailable',
                'kind': kind,
                'provider': provider,
                'model': provider == 'gemini'
                    ? 'gemini-flash-latest'
                    : 'claude-sonnet-5',
              },
            ),
          )
          as AiFailure;

  test("Gemini's quota 429 is a provider state, not ZIVO's daily limit", () {
    final f = providerFailure('quota', 'gemini');
    expect(f.kind, AiFailureKind.unavailable);
    expect(f.issue, AiProviderIssue.quotaExceeded);
    expect(f.kind, isNot(AiFailureKind.dailyLimit));
    expect(aiFailureSuggestsSwitch(f), isTrue);
  });

  testWidgets('every state has its own words; provider copy never says '
      '"usage limit", ZIVO copy says ZIVO', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    final zivo = aiFailureBody(ctx, const AiFailure(AiFailureKind.dailyLimit));
    final zivoTitle = aiFailureTitle(
      ctx,
      const AiFailure(AiFailureKind.dailyLimit),
    );
    expect('$zivoTitle $zivo', contains('ZIVO'));
    expect(zivo, contains('not the AI provider'));

    final states = {
      'claude unavailable': providerFailure('server', 'anthropic'),
      'gemini unavailable': providerFailure('overloaded', 'gemini'),
      'quota': providerFailure('quota', 'gemini'),
      'billing': providerFailure('billing', 'anthropic'),
      'temporary': providerFailure('timeout', 'gemini'),
    };
    final lines = <String>{zivo};
    for (final entry in states.entries) {
      final body = aiFailureBody(ctx, entry.value);
      final title = aiFailureTitle(ctx, entry.value);
      expect(body.toLowerCase(), isNot(contains('usage limit')),
          reason: entry.key);
      expect(body, isNot(contains('Ask settings')), reason: entry.key);
      expect(lines.add(body), isTrue, reason: '${entry.key} reuses copy');
      // The provider is named, so Claude-down and Gemini-down differ.
      expect(title, anyOf(contains('Claude'), contains('Gemini')),
          reason: entry.key);
    }
  });
}

AiUsageRecord _rec({
  required String provider,
  bool fellBack = false,
  String? requested,
  String status = 'ok',
}) => AiUsageRecord(
  feature: 'chat',
  provider: provider,
  model: '',
  tokensIn: 100,
  tokensOut: 10,
  costUsd: 0.01,
  status: status,
  createdAt: null,
  fallbackOccurred: fellBack,
  requestedProvider: requested,
);

void usageMain() {
  test('usage separates the requested model from the one that answered', () {
    final records = [
      _rec(provider: 'gemini'),
      _rec(provider: 'anthropic', fellBack: true, requested: 'gemini'),
      _rec(provider: 'anthropic', fellBack: true, requested: 'gemini'),
      _rec(provider: 'anthropic'),
      _rec(provider: 'gemini', status: 'error'),
    ];
    final gemini = aiProviderStats(records, 'gemini');
    final claude = aiProviderStats(records, 'anthropic');
    // Gemini did 2 requests' work itself (one failed outright) and handed 2
    // to Claude; Claude's tokens/cost include the 2 it took over.
    expect(gemini.totalRequests, 2);
    expect(gemini.failedRequests, 1);
    expect(gemini.handedOffRequests, 2);
    expect(gemini.tookOverRequests, 0);
    expect(claude.totalRequests, 3);
    expect(claude.tookOverRequests, 2);
    expect(claude.handedOffRequests, 0);
    expect(claude.tokensTotal, 330);
  });
}
