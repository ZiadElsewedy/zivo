import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
  fellBack: false,
  createdAt: null,
);

void main() {
  group('aiFailureFrom — no transport or provider text reaches a screen', () {
    AiFailureKind kindOf(Object e) => (aiFailureFrom(e) as AiFailure).kind;

    test("every provider down is 'unavailable', lost connectivity is not", () {
      expect(
        kindOf(
          FirebaseFunctionsException(
            code: 'unavailable',
            message: "ZIVO's AI is taking a short break.",
            details: {'reason': 'ai_unavailable', 'kind': 'billing'},
          ),
        ),
        AiFailureKind.unavailable,
      );
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
    test('legacy ids upgrade; unknown ids fall back to auto', () {
      expect(validAiModelSelection('claude'), 'claude-sonnet');
      expect(validAiModelSelection('gemini'), 'gemini-flash');
      expect(validAiModelSelection('claude-haiku'), 'claude-haiku');
      expect(validAiModelSelection('gpt-9'), 'auto');
      expect(validAiModelSelection(null), 'auto');
    });

    test('each selection shows its provider mark', () {
      expect(aiModelSelectionProvider('claude-haiku'), 'anthropic');
      expect(aiModelSelectionProvider('gemini-pro'), 'gemini');
      expect(aiModelSelectionProvider('auto'), 'auto');
    });
  });

  group('usage records', () {
    test('usageRecords reads every feature, newest first, any schema', () async {
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
        'fellBack': true,
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
      expect(records.first.fellBack, isTrue);
      expect(records[1].failed, isTrue);
      expect(records[1].errorKind, 'rate_limit');
      // Legacy turn: attributed to Claude by its model id, status ok.
      expect(records.last.provider, 'anthropic');
      expect(records.last.status, 'ok');
    });

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
}
