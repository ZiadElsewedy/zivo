/// Why an AI request failed, in terms the app can phrase to a person.
///
/// The repository translates every backend/transport error into one of these
/// before it reaches a screen, so no screen ever renders a provider's or the
/// SDK's own text ("[firebase_functions/deadline-exceeded] DEADLINE EXCEEDED",
/// "Your credit balance is too low…"). Each kind has one localized line — see
/// `aiFailureMessage` in `presentation/ai_labels.dart`.
enum AiFailureKind {
  /// Every AI model ZIVO can use is unavailable right now — the backend tried
  /// its fallback too (`details.reason == 'ai_unavailable'` on the wire).
  /// ZIVO's problem, not the user's: the copy says "short break", never
  /// "credits" or a provider name.
  unavailable,

  /// The user's daily allowance for this feature is used up.
  dailyLimit,

  /// The request ran out of time before an answer came back.
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

/// An AI request that failed for [kind]. Thrown by `AiRepository`'s network
/// methods in place of the transport's own exception.
class AiFailure implements Exception {
  const AiFailure(this.kind);

  final AiFailureKind kind;

  @override
  String toString() => 'AiFailure(${kind.name})';
}
