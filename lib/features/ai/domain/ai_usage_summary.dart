/// A roll-up of one provider's AI usage, aggregated from the owner-readable
/// `users/{uid}/aiUsage` log. Shown in the Ask settings page so the user can
/// see how much each provider has been used.
///
/// The `provider` id matches the routing layer's names ('anthropic', 'gemini',
/// …). Records logged before the backend recorded a `provider` field are
/// attributed by their model id (see `FirebaseAiRepository.usageByProvider`).
///
/// Since usage schema v4 the log covers **every** AI request — chat, plan
/// import, plan generation, food search, voice-to-text — not only chat turns,
/// so [turns] counts requests of any kind.
class AiProviderUsage {
  const AiProviderUsage({
    required this.provider,
    required this.tokensIn,
    required this.tokensOut,
    required this.turns,
    required this.costUsd,
  });

  final String provider;
  final int tokensIn;
  final int tokensOut;

  /// Number of requests (aiUsage docs) attributed to this provider.
  final int turns;

  /// Estimated dollar cost, priced by the backend at the rate of the model
  /// that actually answered (`functions/ai/routing/models.js`). An estimate
  /// from list prices — the UI says "est.".
  final double costUsd;

  int get tokensTotal => tokensIn + tokensOut;
}

/// One AI request as the backend logged it (`functions/ai/shared/
/// usage_log.js` and, for chat, `chat/turn.js`): what it was for, which model
/// did the work, what it cost, and whether it failed or fell back.
class AiUsageRecord {
  const AiUsageRecord({
    required this.feature,
    required this.provider,
    required this.model,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
    required this.status,
    required this.fellBack,
    required this.createdAt,
    this.latencyMs = 0,
    this.errorKind,
  });

  /// What the request was for — 'chat', 'workout_import', 'diet_import',
  /// 'diet_generate', 'food_search', 'transcribe'. A record from before the
  /// field existed was always a chat turn.
  final String feature;

  /// Routing-layer provider that answered ('anthropic' | 'gemini'); on a
  /// failed request, the last one tried.
  final String provider;

  /// Provider-native model id, e.g. 'claude-sonnet-5'. May be empty.
  final String model;

  final int tokensIn;
  final int tokensOut;
  final double costUsd;

  /// 'ok' | 'error' | 'cancelled'.
  final String status;

  /// Whether the preferred model failed and a backup answered.
  final bool fellBack;

  /// Null only for a record whose timestamp couldn't be read.
  final DateTime? createdAt;

  final int latencyMs;

  /// Why a failed request failed ('billing', 'rate_limit', 'timeout', …) —
  /// the backend's classification, never a provider's raw text.
  final String? errorKind;

  bool get failed => status == 'error';
  bool get cancelled => status == 'cancelled';
  int get tokensTotal => tokensIn + tokensOut;
}

/// Totals for one group of [AiUsageRecord]s — a provider, or a feature.
class AiUsageTotals {
  const AiUsageTotals({
    required this.key,
    required this.requests,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
  });

  final String key;
  final int requests;
  final int tokensIn;
  final int tokensOut;
  final double costUsd;

  int get tokensTotal => tokensIn + tokensOut;
}

/// Groups [records] by [keyOf], most expensive group first (then most
/// tokens) — the order a "where did the money go" view wants.
List<AiUsageTotals> aiUsageTotalsBy(
  Iterable<AiUsageRecord> records,
  String Function(AiUsageRecord) keyOf,
) {
  final acc = <String, List<num>>{};
  for (final r in records) {
    final a = acc.putIfAbsent(keyOf(r), () => [0, 0, 0, 0.0]);
    a[0] += 1;
    a[1] += r.tokensIn;
    a[2] += r.tokensOut;
    a[3] += r.costUsd;
  }
  final out = [
    for (final e in acc.entries)
      AiUsageTotals(
        key: e.key,
        requests: e.value[0].toInt(),
        tokensIn: e.value[1].toInt(),
        tokensOut: e.value[2].toInt(),
        costUsd: e.value[3].toDouble(),
      ),
  ];
  out.sort((a, b) {
    final byCost = b.costUsd.compareTo(a.costUsd);
    return byCost != 0 ? byCost : b.tokensTotal.compareTo(a.tokensTotal);
  });
  return out;
}

/// The all-time total of [records] as one [AiUsageTotals] (key `'total'`).
AiUsageTotals aiUsageGrandTotal(Iterable<AiUsageRecord> records) {
  final all = aiUsageTotalsBy(records, (_) => 'total');
  return all.isEmpty
      ? const AiUsageTotals(
          key: 'total',
          requests: 0,
          tokensIn: 0,
          tokensOut: 0,
          costUsd: 0,
        )
      : all.first;
}
