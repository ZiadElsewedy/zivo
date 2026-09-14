/**
 * One shared predicate for "this rejection is an aborted request" — used by
 * both import extractors to tell a user cancellation (client pressed X, the
 * callable's `response.signal` fired) apart from a genuine failure.
 *
 * Matched by `err.name` so this needs no `@anthropic-ai/sdk` import and stays
 * offline-testable: the SDK throws `APIUserAbortError`, and a native
 * `AbortController` throws an `AbortError` — both carry the name.
 */

/**
 * True when `err` is the rejection an aborted request throws.
 * @param {*} err
 * @return {boolean}
 */
function isAbortError(err) {
  const name = err && err.name;
  return name === "AbortError" || name === "APIUserAbortError";
}

module.exports = {isAbortError};
