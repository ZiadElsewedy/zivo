/**
 * Provider-error classification — the one place that decides what a failed
 * model call MEANS, so the router (`../routing/router.js`) can decide whether
 * another provider might succeed, and the callables can decide what the user
 * is told.
 *
 * The line it draws: fall back whenever the PROVIDER can't serve us — it's
 * down, overloaded, rate-limited, out of credit, rejecting our key, or no
 * longer offers the model — but NOT when the provider rejected our REQUEST as
 * malformed. A malformed request (a bug, or an unsupported schema) would be
 * rejected by the next provider the same way while masking the real cause.
 *
 * Billing is the case that used to slip through: Anthropic reports an
 * exhausted credit balance as a plain **400** `invalid_request_error`
 * ("Your credit balance is too low…"), which a status-only rule reads as "our
 * request is bad" and rethrows — so an out-of-credit Claude never fell back to
 * Gemini, and the raw provider text reached the user. The message is therefore
 * checked alongside the status.
 *
 * Duck-typed on the SDK error shape (`status`, `name`, `message`) rather than
 * importing `@anthropic-ai/sdk`/`@google/genai` — both SDKs surface a numeric
 * `.status` on their API errors, and both put the provider's own error JSON in
 * `.message`.
 */

/**
 * What kind of failure a provider call hit. Every kind except `bad_request`
 * is worth trying another provider for.
 * @enum {string}
 */
const ProviderErrorKind = {
  TIMEOUT: "timeout",
  NETWORK: "network",
  OVERLOADED: "overloaded",
  SERVER: "server",
  RATE_LIMIT: "rate_limit",
  BILLING: "billing",
  AUTH: "auth",
  MODEL_UNAVAILABLE: "model_unavailable",
  BAD_REQUEST: "bad_request",
};

/**
 * Joins alternatives into one case-insensitive regex — kept as a list so each
 * provider's phrasing is readable on its own line.
 * @param {!Array<string>} parts
 * @return {!RegExp}
 */
const anyOf = (parts) => new RegExp(parts.join("|"), "i");

const BILLING_RE = anyOf([
  "credit balance", // Anthropic: "Your credit balance is too low…" (a 400)
  "billing",
  "insufficient[_ ](funds|credit|quota)",
  "exceeded your current quota",
  "spend(ing)? limit",
  "payment required",
  "RESOURCE_EXHAUSTED", // Gemini quota exhaustion (a 429)
]);
const AUTH_RE = anyOf([
  "api[_ -]?key (not valid|invalid)", // Gemini: "API key not valid" (a 400)
  "API_KEY_INVALID",
  "invalid x-api-key", // Anthropic
  "authentication_error",
  "permission_error",
  "PERMISSION_DENIED",
  "UNAUTHENTICATED",
]);
const MODEL_RE = anyOf([
  "model[^.]{0,80}(not found|not supported|no longer available|" +
    "does not exist|is not available)",
  "not_found_error",
]);

/**
 * @param {*} err The error a provider's `generate` rejected with.
 * @return {string} A `ProviderErrorKind`.
 */
function classifyProviderError(err) {
  const status = err && typeof err.status === "number" ? err.status : undefined;
  const name =
    (err && (err.name || (err.constructor && err.constructor.name))) || "";
  const message = (err && err.message) || "";

  // A deadline we set (see the router's per-attempt timeout) or an SDK
  // timeout: the request never got an answer in time.
  if (name === "AbortError" || /timeout/i.test(name) ||
      /tim(e|ed) ?out|deadline/i.test(message)) {
    return ProviderErrorKind.TIMEOUT;
  }
  // No HTTP status at all: the request never got a response (connection
  // refused/reset, DNS failure) — the provider is unreachable.
  if (status === undefined) return ProviderErrorKind.NETWORK;

  // Billing is checked before the status buckets because it arrives as a 400
  // (Anthropic), a 402, a 403, or a 429 RESOURCE_EXHAUSTED (Gemini), and in
  // every form it means "this provider won't serve us until someone pays".
  if (status === 402 || BILLING_RE.test(message)) {
    return ProviderErrorKind.BILLING;
  }
  if (status === 401 || status === 403 || AUTH_RE.test(message)) {
    return ProviderErrorKind.AUTH;
  }
  if (status === 404 || MODEL_RE.test(message)) {
    return ProviderErrorKind.MODEL_UNAVAILABLE;
  }
  if (status === 429) return ProviderErrorKind.RATE_LIMIT;
  // Anthropic's 529 and a 503 are "overloaded, try later"; any other 5xx is a
  // provider-side error. Both are the provider's problem.
  if (status === 529 || status === 503) return ProviderErrorKind.OVERLOADED;
  if (status >= 500) return ProviderErrorKind.SERVER;
  // Any other 4xx: the provider rejected the request itself.
  return ProviderErrorKind.BAD_REQUEST;
}

/**
 * @param {*} err
 * @return {boolean} `true` when another provider might succeed where this one
 *   failed; `false` for a malformed request, which a fallback would only
 *   repeat.
 */
function isProviderFailure(err) {
  return classifyProviderError(err) !== ProviderErrorKind.BAD_REQUEST;
}

/**
 * Kinds that mean "this provider is out of service for us for a while" rather
 * than "this one call was unlucky" — the router stops sending traffic to a
 * provider that hit one of these for a cool-down window, so every call during
 * a Claude credit outage doesn't pay a failed round-trip first.
 * @param {string} kind
 * @return {boolean}
 */
function isSustainedOutage(kind) {
  return kind === ProviderErrorKind.BILLING ||
    kind === ProviderErrorKind.AUTH;
}

/**
 * Thrown by the router when EVERY route for a capability failed with a
 * provider failure — nothing the user did, and nothing a retry this second is
 * likely to fix. Callables map it to a friendly `unavailable` message; the
 * provider's own error text never reaches the user.
 */
class AiUnavailableError extends Error {
  /**
   * @param {string} kind The last attempt's `ProviderErrorKind`.
   * @param {!Array<{provider: string, model: string, kind: string}>} attempts
   * @param {*=} cause The last provider error, kept for server logs.
   */
  constructor(kind, attempts, cause) {
    super(`All AI providers failed (last: ${kind}).`);
    this.name = "AiUnavailableError";
    this.kind = kind;
    this.attempts = attempts;
    this.cause = cause;
  }
}

module.exports = {
  ProviderErrorKind,
  classifyProviderError,
  isProviderFailure,
  isSustainedOutage,
  AiUnavailableError,
};
