/// A roll-up of one provider's AI usage, aggregated from the owner-readable
/// `users/{uid}/aiUsage` log (written per turn by the backend). Shown in the
/// Ask settings page so the user can see how much each model has been used.
///
/// The `provider` id matches the routing layer's names ('anthropic', 'gemini',
/// …). Turns logged before the backend recorded a `provider` field are
/// attributed by their model id (see `FirebaseAiRepository.usageByProvider`).
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

  /// Number of turns (aiUsage docs) attributed to this provider.
  final int turns;

  /// Estimated dollar cost. **Approximate for Gemini** — the backend's cost
  /// logging currently prices every turn at Anthropic's per-token rates, so a
  /// Gemini figure is a rough upper bound, not a bill. The UI says "est.".
  final double costUsd;

  int get tokensTotal => tokensIn + tokensOut;
}
