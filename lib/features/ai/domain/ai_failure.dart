/// Why an AI request failed, in terms the app can phrase to a person.
///
/// The repository translates every backend/transport error into one of these
/// before it reaches a screen, so no screen ever renders a provider's or the
/// SDK's own text ("[firebase_functions/deadline-exceeded] DEADLINE EXCEEDED",
/// "Your credit balance is too low…"). The words live in
/// `presentation/ai_labels.dart` (`aiFailureTitle` / `aiFailureBody`).
enum AiFailureKind {
  /// The active model's provider couldn't answer — see [AiFailure.provider]
  /// and [AiFailure.issue] for which one and why. ZIVO uses exactly one model
  /// per request, so this is never silently retried elsewhere; the fix is to
  /// wait, or switch the active model.
  unavailable,

  /// The user's daily allowance for this feature is used up.
  dailyLimit,

  /// The app gave up waiting before the server answered at all.
  timeout,

  /// The phone couldn't reach ZIVO's servers.
  network,

  /// Signed out, or the app's integrity check (App Check) was rejected.
  auth,

  /// The backend function isn't deployed (an app ahead of its backend).
  notDeployed,

  /// Anything else — a server-side failure with no more specific cause.
  unknown,
}

/// What exactly was wrong with the provider, for [AiFailureKind.unavailable].
/// Mirrors the backend's classification (`functions/ai/providers/
/// classify.js`), minus anything that isn't the provider's fault.
enum AiProviderIssue {
  /// The provider account's credit/quota is used up.
  outOfCredit,

  /// The provider rejected ZIVO's key — misconfigured on the server.
  notConfigured,

  /// Rate-limited: too many requests right now.
  busy,

  /// The provider reports it's overloaded.
  overloaded,

  /// The model didn't answer before the server's deadline.
  noResponse,

  /// The model id is no longer offered.
  modelRetired,

  /// Down, erroring, or unreachable from the server.
  down,
}

/// An AI request that failed for [kind]. Thrown by `AiRepository`'s network
/// methods in place of the transport's own exception.
class AiFailure implements Exception {
  const AiFailure(this.kind, {this.provider, this.issue});

  final AiFailureKind kind;

  /// The provider that failed ('anthropic' | 'gemini'), when the server said.
  final String? provider;

  /// Why the provider failed, for [AiFailureKind.unavailable].
  final AiProviderIssue? issue;

  @override
  String toString() =>
      'AiFailure(${kind.name}${provider == null ? '' : ', $provider'}'
      '${issue == null ? '' : ', ${issue!.name}'})';
}

/// The backend's `details.kind` → [AiProviderIssue].
AiProviderIssue aiProviderIssueFrom(Object? kind) => switch (kind) {
  'billing' => AiProviderIssue.outOfCredit,
  'auth' => AiProviderIssue.notConfigured,
  'rate_limit' => AiProviderIssue.busy,
  'overloaded' => AiProviderIssue.overloaded,
  'timeout' => AiProviderIssue.noResponse,
  'model_unavailable' => AiProviderIssue.modelRetired,
  _ => AiProviderIssue.down,
};
