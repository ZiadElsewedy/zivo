import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/ai/data/firebase_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/ai/domain/ai_model_selection.dart';
import 'package:zivo/features/ai/domain/ai_usage_summary.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

AiUsageRecord _record({
  String feature = 'chat',
  String provider = 'anthropic',
  int tokensIn = 0,
  int tokensOut = 0,
  double costUsd = 0,
}) => AiUsageRecord(
  feature: feature,
  provider: provider,
  model: '',
  tokensIn: tokensIn,
  tokensOut: tokensOut,
  costUsd: costUsd,
  status: 'ok',
  createdAt: null,
);

void main() {
  group('aiFailureFrom — no transport or provider text reaches a screen', () {
    AiFailureKind kindOf(Object e) => (aiFailureFrom(e) as AiFailure).kind;

    test("a provider failure is 'unavailable' with WHO and WHY; lost "
        'connectivity is not', () {
      final f =
          aiFailureFrom(
                FirebaseFunctionsException(
                  code: 'unavailable',
                  message: 'Claude is unavailable',
                  details: {
                    'reason': 'ai_unavailable',
                    'kind': 'billing',
                    'provider': 'anthropic',
                    'model': 'claude-sonnet-5',
                  },
                ),
              )
              as AiFailure;
      expect(f.kind, AiFailureKind.unavailable);
      expect(f.provider, 'anthropic');
      expect(f.issue, AiProviderIssue.outOfCredit);
      expect(
        kindOf(
          FirebaseFunctionsException(code: 'unavailable', message: 'offline'),
        ),
        AiFailureKind.network,
      );
    });

    test('deadline, quota, auth and a missing function each map', () {
      FirebaseFunctionsException e(String code) =>
          FirebaseFunctionsException(code: code, message: 'x');
      expect(kindOf(e('deadline-exceeded')), AiFailureKind.timeout);
      expect(kindOf(e('resource-exhausted')), AiFailureKind.dailyLimit);
      expect(kindOf(e('unauthenticated')), AiFailureKind.auth);
      expect(kindOf(e('not-found')), AiFailureKind.notDeployed);
      expect(kindOf(e('internal')), AiFailureKind.unknown);
    });

    test('the STREAMING call\'s raw PlatformException is mapped too', () {
      // httpsCallable.stream() forwards native errors via `yield*` without
      // converting them — the reason a failed streamed turn used to read as
      // "couldn't reach ZIVO" whatever the cause.
      final f =
          aiFailureFrom(
                PlatformException(
                  code: 'firebase_functions',
                  message: 'Gemini is getting too many requests.',
                  details: {
                    'code': 'unavailable',
                    'message': 'Gemini is getting too many requests.',
                    'additionalData': {
                      'reason': 'ai_unavailable',
                      'kind': 'rate_limit',
                      'provider': 'gemini',
                    },
                  },
                ),
              )
              as AiFailure;
      expect(f.kind, AiFailureKind.unavailable);
      expect(f.provider, 'gemini');
      expect(f.issue, AiProviderIssue.busy);

      expect(
        kindOf(
          PlatformException(
            code: 'firebase_functions',
            details: {'code': 'deadline-exceeded', 'message': 'x'},
          ),
        ),
        AiFailureKind.timeout,
      );
    });

    test('every backend kind maps to its issue', () {
      expect(aiProviderIssueFrom('auth'), AiProviderIssue.notConfigured);
      expect(aiProviderIssueFrom('overloaded'), AiProviderIssue.overloaded);
      expect(aiProviderIssueFrom('timeout'), AiProviderIssue.noResponse);
      expect(
        aiProviderIssueFrom('model_unavailable'),
        AiProviderIssue.modelRetired,
      );
      expect(aiProviderIssueFrom('server'), AiProviderIssue.down);
    });

    test('a non-transport error passes through untouched', () {
      final original = StateError('parse');
      expect(identical(aiFailureFrom(original), original), isTrue);
    });

    test('generateDietPlan rethrows a callable failure as an AiFailure', () {
      final repo = FirebaseAiRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u'),
        invokeDietGenerate: (_, _) async => throw FirebaseFunctionsException(
          code: 'deadline-exceeded',
          message: 'DEADLINE EXCEEDED',
        ),
      );
      expect(
        repo.generateDietPlan(
          preferences: const PlanPreferences(mealsPerDay: 3),
        ),
        throwsA(
          isA<AiFailure>().having((f) => f.kind, 'kind', AiFailureKind.timeout),
        ),
      );
    });
  });

  group('model selection ids', () {
    test('one active model: two choices, Sonnet by default', () {
      expect(kAiModelSelections, ['claude-sonnet', 'gemini-flash']);
      expect(validAiModelSelection(null), 'claude-sonnet');
      expect(validAiModelSelection('gpt-9'), 'claude-sonnet');
    });

    test('retired and legacy ids upgrade to a model that exists', () {
      expect(validAiModelSelection('auto'), 'claude-sonnet');
      expect(validAiModelSelection('claude'), 'claude-sonnet');
      expect(validAiModelSelection('gemini'), 'gemini-flash');
      expect(validAiModelSelection('gemini-pro'), 'gemini-flash');
      // Claude Haiku, removed 2026-09-24 — one model per provider now.
      expect(validAiModelSelection('claude-haiku'), 'claude-sonnet');
    });

    test('each selection shows its provider mark', () {
      expect(aiModelSelectionProvider('claude-sonnet'), 'anthropic');
      expect(aiModelSelectionProvider('gemini-flash'), 'gemini');
    });
  });

  group('usage records', () {
    test(
      'usageRecords reads every feature, newest first, any schema',
      () async {
        final firestore = FakeFirebaseFirestore();
        final log = firestore
            .collection('users')
            .doc('u')
            .collection('aiUsage');
        // A pre-v4 chat turn: no feature, no status.
        await log.add({
          'model': 'claude-sonnet-5',
          'tokensIn': 100,
          'tokensOut': 10,
          'costUsd': 0.0005,
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 20)),
        });
        await log.add({
          'feature': 'diet_generate',
          'provider': 'gemini',
          'model': 'gemini-flash-latest',
          'tokensIn': 6000,
          'tokensOut': 3000,
          'costUsd': 0.009,
          'status': 'ok',
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 23)),
        });
        await log.add({
          'feature': 'workout_import',
          'provider': 'gemini',
          'status': 'error',
          'errorKind': 'rate_limit',
          'tokensIn': 0,
          'tokensOut': 0,
          'costUsd': 0,
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 22)),
        });
        final repo = FirebaseAiRepository(
          firestore: firestore,
          uidSource: _signedInAs('u'),
        );

        final records = await repo.usageRecords();

        expect(records.map((r) => r.feature), [
          'diet_generate',
          'workout_import',
          'chat',
        ]);
        expect(records[1].failed, isTrue);
        expect(records[1].errorKind, 'rate_limit');
        // Legacy turn: attributed to Claude by its model id, status ok.
        expect(records.last.provider, 'anthropic');
        expect(records.last.status, 'ok');
      },
    );

    test('totals group by provider and by feature, most expensive first', () {
      final records = [
        _record(tokensIn: 100, tokensOut: 10, costUsd: 0.01),
        _record(
          feature: 'diet_import',
          tokensIn: 5000,
          tokensOut: 900,
          costUsd: 0.03,
        ),
        _record(provider: 'gemini', tokensIn: 400, costUsd: 0.001),
      ];

      final byProvider = aiUsageTotalsBy(records, (r) => r.provider);
      expect(byProvider.map((t) => t.key), ['anthropic', 'gemini']);
      expect(byProvider.first.requests, 2);
      expect(byProvider.first.tokensIn, 5100);

      final byFeature = aiUsageTotalsBy(records, (r) => r.feature);
      expect(byFeature.map((t) => t.key), ['diet_import', 'chat']);
      expect(byFeature.last.requests, 2);

      final total = aiUsageGrandTotal(records);
      expect(total.requests, 3);
      expect(total.costUsd, closeTo(0.041, 1e-9));
      expect(aiUsageGrandTotal(const []).requests, 0);
    });
  });

  group('per-provider stats (the usage page)', () {
    AiUsageRecord r(
      String provider,
      String feature, {
      int tin = 0,
      int tout = 0,
      double cost = 0,
      String status = 'ok',
    }) => AiUsageRecord(
      feature: feature,
      provider: provider,
      model: '',
      tokensIn: tin,
      tokensOut: tout,
      costUsd: cost,
      status: status,
      createdAt: null,
    );

    final records = [
      r('gemini', 'chat', tin: 1000, tout: 200, cost: 0.001),
      r('gemini', 'chat', tin: 3000, tout: 400, cost: 0.003),
      r('gemini', 'diet_generate', tin: 6000, tout: 3000, cost: 0.008),
      r('gemini', 'diet_import', tin: 9000, tout: 1000, cost: 0.004),
      r('gemini', 'transcribe', tin: 400, tout: 40, cost: 0.0002),
      r('gemini', 'chat', status: 'error'),
      r('anthropic', 'chat', tin: 13000, tout: 150, cost: 0.04),
    ];

    test('counts requests by type, tokens and cost for ONE provider', () {
      final g = aiProviderStats(records, 'gemini');
      expect(g.totalRequests, 6);
      expect(g.chatRequests, 3);
      expect(g.generateRequests, 1);
      expect(g.importRequests, 1);
      expect(g.otherRequests, 1);
      expect(g.failedRequests, 1);
      expect(g.tokensIn, 19400);
      expect(g.tokensOut, 4640);
      expect(g.tokensTotal, 24040);
      expect(g.costUsd, closeTo(0.0162, 1e-9));
    });

    test('cost per request averages completed requests only', () {
      final g = aiProviderStats(records, 'gemini');
      // 5 completed; the failed one produced nothing and must not dilute it.
      expect(g.costPerRequestUsd, closeTo(0.0162 / 5, 1e-9));
    });

    test('a provider with nothing logged is all zeros', () {
      final a = aiProviderStats(const [], 'anthropic');
      expect(a.totalRequests, 0);
      expect(a.costPerRequestUsd, 0);
    });
  });
  group('aiFailureFromStreamChunk — the reason a streamed turn announces', () {
    // The iOS plugin drops a streamed callable error's code/details, so the
    // server repeats the cause as a final data chunk.
    test('an ai_unavailable chunk becomes the provider-named failure', () {
      final f = aiFailureFromStreamChunk({
        'type': 'error',
        'reason': 'ai_unavailable',
        'provider': 'gemini',
        'model': 'gemini-flash-latest',
        'kind': 'overloaded',
      });
      expect(f, isNotNull);
      expect(f!.kind, AiFailureKind.unavailable);
      expect(f.provider, 'gemini');
      expect(f.issue, AiProviderIssue.overloaded);
    });

    test('quota and billing keep their own issue', () {
      AiProviderIssue? issueOf(String kind) => aiFailureFromStreamChunk({
        'type': 'error',
        'reason': 'ai_unavailable',
        'provider': 'gemini',
        'kind': kind,
      })?.issue;
      expect(issueOf('quota'), AiProviderIssue.quotaExceeded);
      expect(issueOf('billing'), AiProviderIssue.outOfCredit);
    });

    test('any other chunk is not a failure', () {
      expect(aiFailureFromStreamChunk({'type': 'delta', 'text': 'hi'}), isNull);
      expect(
        aiFailureFromStreamChunk({'type': 'error', 'reason': 'other'}),
        isNull,
      );
      expect(aiFailureFromStreamChunk('error'), isNull);
      expect(aiFailureFromStreamChunk(null), isNull);
    });
  });
}
