/// The recorded cost/telemetry of a single Ask turn — the `aiUsage` doc the
/// backend logs (see `functions/ai/chat/turn.js`), paired to the assistant
/// message it produced by their shared `clientTurnId`.
///
/// This is what the per-message "turn details" sheet reads. Fields mirror the
/// backend's schema-v3 usage doc; the two token-slice fields
/// ([uncachedTokensIn], [toolResultTokens]) are absent on pre-v3 turns and are
/// derived / zeroed when reading those (see `FirebaseAiRepository.usageForTurn`).
class AiTurnUsage {
  const AiTurnUsage({
    required this.provider,
    required this.model,
    required this.tokensIn,
    required this.uncachedTokensIn,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.tokensOut,
    required this.toolResultTokens,
    required this.tools,
    required this.iterations,
    required this.latencyMs,
    required this.costUsd,
  });

  /// Routing-layer provider id: 'anthropic' | 'gemini' (never empty — a legacy
  /// turn is attributed from its [model] id).
  final String provider;

  /// Provider-native model id that actually answered, e.g. 'claude-sonnet-5'.
  final String model;

  /// Total input volume: uncached + cache read + cache write.
  final int tokensIn;

  /// Input tokens billed at full price (not served from the prompt cache).
  final int uncachedTokensIn;

  /// Input tokens read back from the prompt cache (~0.1x price).
  final int cacheReadTokens;

  /// Input tokens written into the prompt cache (~1.25x price).
  final int cacheWriteTokens;

  /// Output (generated) tokens.
  final int tokensOut;

  /// Approximate tokens of tool-result JSON fed back to the model this turn.
  final int toolResultTokens;

  /// Names of the tools the model called this turn, in call order.
  final List<String> tools;

  /// Model↔tool round-trips the turn took.
  final int iterations;

  /// Wall-clock time the turn took, in milliseconds.
  final int latencyMs;

  /// Estimated cost in USD, priced at [provider]'s rate.
  final double costUsd;

  int get tokensTotal => tokensIn + tokensOut;
}
