/**
 * `isProviderFailure` — the one predicate the chat router
 * (`../routing/router.js`) uses to decide whether an error from a provider's
 * `generate` is worth failing over to the next route, or should be rethrown
 * as-is.
 *
 * This is the line requirement #2 draws: fall back on an actual provider/API
 * problem (the provider is down, rate-limited, or never answered), but NOT on
 * a request the provider rejected as malformed — a 4xx (other than 429) means
 * OUR request is the problem (a bug, or an unsupported schema), and the next
 * provider would reject the identical request the same way while masking the
 * real cause. Application-level errors (invalid user input, tool bugs) never
 * reach here at all: they're thrown in `../chat/turn.js` OUTSIDE the model
 * call, so the router never sees them.
 *
 * Duck-typed on the SDK error shape (`status`, `name`) rather than importing
 * `@anthropic-ai/sdk`/`@google/genai` — the same approach
 * `../speech/providers/gemini_speech_provider.js`'s `classifyError` takes, and
 * both SDKs surface a numeric `.status` on their API errors.
 */

/**
 * @param {*} err The error a provider's `generate` rejected with.
 * @return {boolean} `true` when the error is a transient/transport provider
 *   failure (5xx, 429, timeout, or no response at all) that a fallback route
 *   might succeed at; `false` for a 4xx the provider deliberately rejected
 *   (a bad request), which a fallback would only repeat.
 */
function isProviderFailure(err) {
  const status = err && typeof err.status === "number" ? err.status : undefined;
  const name = (err && (err.name || (err.constructor && err.constructor.name))) || "";
  const message = (err && err.message) || "";

  // A client-side deadline (fetch abort) or an SDK-reported timeout: the
  // request never got an answer in time — worth trying another provider.
  if (name === "AbortError" || /timeout/i.test(name) ||
      /tim(e|ed) ?out/i.test(message)) {
    return true;
  }
  // No HTTP status at all means the request never got a response (connection
  // refused/reset, DNS failure): the provider is unreachable, not our request.
  if (status === undefined) return true;
  // 5xx (provider error) and 429 (rate limit / quota exhaustion) are the
  // provider's problem, not the request's — fail over.
  if (status >= 500 || status === 429) return true;
  // Any other 4xx: the provider rejected the request itself. Failing over
  // would send the same rejected request to another provider and hide the bug.
  return false;
}

module.exports = {isProviderFailure};
