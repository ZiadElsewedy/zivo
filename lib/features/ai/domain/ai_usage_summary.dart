/// A roll-up of one provider's AI usage, aggregated from the owner-readable
/// `users/{uid}/aiUsage` log — how much each provider has been used.
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
/// did the work, what it cost, and whether it failed.
class AiUsageRecord {
  const AiUsageRecord({
    required this.feature,
    required this.provider,
    required this.model,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
    required this.status,
    required this.createdAt,
    this.latencyMs = 0,
    this.errorKind,
    this.fallbackOccurred = false,
    this.fallbackReason,
    this.requestedProvider,
    this.requestedModel,
  });

  /// What the request was for — 'chat', 'workout_import', 'diet_import',
  /// 'diet_generate', 'food_search', 'transcribe'. A record from before the
  /// field existed was always a chat turn.
  final String feature;

  /// Routing-layer provider that answered ('anthropic' | 'gemini'); on a
  /// failed request, the one that failed.
  final String provider;

  /// Provider-native model id, e.g. 'claude-sonnet-5'. May be empty.
  final String model;

  final int tokensIn;
  final int tokensOut;
  final double costUsd;

  /// 'ok' | 'error' | 'cancelled'.
  final String status;

  /// Null only for a record whose timestamp couldn't be read.
  final DateTime? createdAt;

  final int latencyMs;

  /// Why a failed request failed ('billing', 'rate_limit', 'timeout', …) —
  /// the backend's classification, never a provider's raw text.
  final String? errorKind;

  /// Whether the router had to fall back to the other provider — the
  /// requested model's provider hit a transient failure and [provider]/
  /// [model] name who actually answered instead
  /// (`functions/ai/routing/router.js`).
  final bool fallbackOccurred;

  /// Why the fallback happened ('overloaded', 'rate_limit', 'timeout', …) —
  /// the same classification as [errorKind], but for the REQUESTED provider's
  /// failure, not this request's own outcome. Null unless [fallbackOccurred].
  final String? fallbackReason;

  /// The provider the user's active model actually named, before the router
  /// fell back. Null unless [fallbackOccurred].
  final String? requestedProvider;

  /// The provider-native model id the user's active model named, before the
  /// router fell back. Null unless [fallbackOccurred].
  final String? requestedModel;

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

/// What a request was for, grouped the way the usage page counts them.
enum AiRequestType { chat, generate, import, other }

/// [feature] → its [AiRequestType]. Food search and voice-to-text, and any
/// feature a newer backend adds, count as [AiRequestType.other].
AiRequestType aiRequestTypeOf(String feature) => switch (feature) {
  'chat' => AiRequestType.chat,
  'diet_generate' => AiRequestType.generate,
  'workout_import' || 'diet_import' => AiRequestType.import,
  _ => AiRequestType.other,
};

/// One provider's usage, the way the AI usage page shows it: how many
/// requests of each type, the tokens, the cost, and what an average request
/// costs.
class AiProviderStats {
  const AiProviderStats({
    required this.provider,
    required this.totalRequests,
    required this.chatRequests,
    required this.generateRequests,
    required this.importRequests,
    required this.otherRequests,
    required this.failedRequests,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
    required this.costPerRequestUsd,
    this.tookOverRequests = 0,
    this.handedOffRequests = 0,
  });

  final String provider;
  final int totalRequests;
  final int chatRequests;
  final int generateRequests;
  final int importRequests;
  final int otherRequests;
  final int failedRequests;

  /// Requests this provider ANSWERED after the user's active model (the other
  /// provider) failed — counted in [totalRequests], tokens and cost.
  final int tookOverRequests;

  /// Requests the user sent to THIS provider that it couldn't answer, so the
  /// other provider did — logged under the other provider (it did the work
  /// and holds the tokens/cost), counted here so a provider that keeps
  /// failing is visible on its own page.
  final int handedOffRequests;

  final int tokensIn;
  final int tokensOut;
  final double costUsd;

  /// Average cost of a **completed** request — a failed or cancelled one
  /// generated nothing and costs ~nothing, so counting it would make the
  /// average look cheaper than a real answer is.
  final double costPerRequestUsd;

  int get tokensTotal => tokensIn + tokensOut;
}

/// [provider]'s stats over [records] (records of other providers are
/// ignored).
AiProviderStats aiProviderStats(
  Iterable<AiUsageRecord> records,
  String provider,
) {
  var total = 0, chat = 0, generate = 0, imports = 0, other = 0, failed = 0;
  var completed = 0, tokensIn = 0, tokensOut = 0;
  var cost = 0.0, completedCost = 0.0;
  var tookOver = 0, handedOff = 0;
  for (final r in records) {
    if (r.fallbackOccurred && r.requestedProvider == provider &&
        r.provider != provider) {
      handedOff++;
    }
    if (r.provider != provider) continue;
    total++;
    if (r.fallbackOccurred) tookOver++;
    switch (aiRequestTypeOf(r.feature)) {
      case AiRequestType.chat:
        chat++;
      case AiRequestType.generate:
        generate++;
      case AiRequestType.import:
        imports++;
      case AiRequestType.other:
        other++;
    }
    if (r.failed) failed++;
    if (!r.failed && !r.cancelled) {
      completed++;
      completedCost += r.costUsd;
    }
    tokensIn += r.tokensIn;
    tokensOut += r.tokensOut;
    cost += r.costUsd;
  }
  return AiProviderStats(
    provider: provider,
    totalRequests: total,
    chatRequests: chat,
    generateRequests: generate,
    importRequests: imports,
    otherRequests: other,
    failedRequests: failed,
    tokensIn: tokensIn,
    tokensOut: tokensOut,
    costUsd: cost,
    costPerRequestUsd: completed == 0 ? 0 : completedCost / completed,
    tookOverRequests: tookOver,
    handedOffRequests: handedOff,
  );
}
