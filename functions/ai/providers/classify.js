/**
 * Provider-error classification — the one place that decides what a failed
 * model call MEANS, so the callables can tell the user WHY their AI request
 * failed ("Claude is out of credit", "Gemini didn't respond") and the router
 * (`../routing/router.js`) can tell a provider problem from our own bug.
 *
 * The line it draws: a provider that can't serve us — down, overloaded,
 * rate-limited, out of credit, rejecting our key, no longer offering the
 * model, or silent past the deadline — is `AiUnavailableError` territory. A
 * request the provider rejected as malformed is OUR bug and is rethrown.
 *
 * Billing is the case that used to slip through: Anthropic reports an
 * exhausted credit balance as a plain **400** `invalid_request_error`
 * ("Your credit balance is too low…"), which a status-only rule reads as "our
 * request is bad" — and the raw provider text reached the user. The message is
 * therefore checked alongside the status.
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
  // The provider project's own API quota is used up (Gemini's 429
  // RESOURCE_EXHAUSTED — per-minute or per-day, e.g. the free tier's 20
  // requests/day). Not a credit balance: nobody has to pay for it to lift,
  // it resets on the provider's own clock.
  QUOTA: "quota",
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

// Checked BEFORE `BILLING_RE`: Gemini's quota 429 reads "You exceeded your
// current quota, please check your plan and billing details … Quota exceeded
// for metric: …free_tier_requests, limit: 20", and the word "billing" in it
// used to classify every Gemini rate/quota hit as an out-of-credit account.
const QUOTA_RE = anyOf([
  "RESOURCE_EXHAUSTED", // Gemini quota exhaustion (a 429)
  "exceeded your current quota",
  "quota exceeded",
  "insufficient[_ ]quota",
]);
const BILLING_RE = anyOf([
  "credit balance", // Anthropic: "Your credit balance is too low…" (a 400)
  "billing",
  "insufficient[_ ](funds|credit)",
  "spend(ing)? limit",
  "payment required",
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

  // Quota, then billing, are checked before the status buckets: quota
  // arrives as a 429 whose text mentions billing, and billing arrives as a
  // 400 (Anthropic), a 402 or a 403 — in every form it means "this provider
  // won't serve us until someone pays".
  if (status !== 402 && QUOTA_RE.test(message)) return ProviderErrorKind.QUOTA;
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
 * Whether a `ProviderErrorKind` is worth retrying/falling back for — a
 * transient condition where the SAME request might succeed a moment later or
 * against another provider: the provider is down, overloaded, rate-limited, or
 * didn't respond in time.
 *
 * Deliberately narrower than `isProviderFailure`: `quota`, `billing`, `auth`
 * and `model_unavailable` won't clear in the next 350ms, so retrying the SAME
 * provider would only burn a request. They still fall back to the other
 * provider (`canFallBackFor`) — visibly: the turn's timeline says the model
 * was unavailable and which one took over, and the usage record keeps the
 * failed attempt and its kind, so a key/billing problem is never hidden. See
 * `../routing/router.js`'s retry-then-fallback.
 * @param {string} kind A `ProviderErrorKind`.
 * @return {boolean}
 */
function isTransientFailure(kind) {
  return kind === ProviderErrorKind.TIMEOUT ||
    kind === ProviderErrorKind.NETWORK ||
    kind === ProviderErrorKind.OVERLOADED ||
    kind === ProviderErrorKind.SERVER ||
    kind === ProviderErrorKind.RATE_LIMIT;
}

/**
 * Whether another PROVIDER might answer where this one failed — every
 * provider-side failure (down, busy, out of quota or credit, key rejected,
 * model retired), but never a request the provider rejected as malformed
 * (`bad_request`: our bug, and the other provider would be sent the same
 * thing). Distinct from `isTransientFailure`, which decides whether the SAME
 * provider is worth one more try.
 * @param {string} kind A `ProviderErrorKind`.
 * @return {boolean}
 */
function canFallBackFor(kind) {
  return kind !== ProviderErrorKind.BAD_REQUEST;
}

/**
 * Thrown by the router when the active model's provider couldn't answer —
 * nothing the user did. Carries WHICH provider and WHY (`kind`), so the
 * callables can say "Claude is unavailable — out of credit" instead of a
 * generic failure; the provider's own error text stays in the server log.
 */
class AiUnavailableError extends Error {
  /**
   * @param {string} kind The last attempt's `ProviderErrorKind`.
   * @param {!Array<{provider: string, model: string, kind: string}>} attempts
   * @param {*=} cause The last provider error, kept for server logs.
   */
  constructor(kind, attempts, cause) {
    const who = attempts.length ? attempts[attempts.length - 1].provider : "?";
    super(`AI provider ${who} unavailable (${kind}).`);
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
  isTransientFailure,
  canFallBackFor,
  AiUnavailableError,
};
