/**
 * ZIVO — shared one-time-code (OTP) core.
 *
 * The pure decision logic behind BOTH server OTP flows: email verification
 * (`emailOtps/{uid}`) and password reset (`passwordResetOtps/{uid}`). Kept
 * free of any `firebase-admin` import so it stays unit-testable under plain
 * `node --test` (mirroring ./activity.js) — the callables in ../index.js wrap
 * a Firestore transaction around `decideSend`/`decideVerify` and translate the
 * returned decision into an `HttpsError` or a success side-effect.
 *
 * Security posture (all enforced here — the client is never trusted):
 *   • The code is generated with a CSPRNG and NEVER stored or logged in
 *     plaintext. Only an HMAC-SHA256 digest keyed by a server secret
 *     (OTP_PEPPER) plus a per-code random salt is persisted, so a database
 *     leak does not expose codes even against offline brute force.
 *   • Single-use: the code fields are cleared the moment a code verifies.
 *   • Expiry: codes are valid for `ttlMs`.
 *   • Attempt cap: `maxAttempts` wrong guesses invalidate the code.
 *   • Resend cooldown (`cooldownMs`) and an hourly send cap (`maxSendsPerHour`)
 *     throttle abuse — and, critically, that throttle accounting
 *     (`windowStartAt`/`sendCount`/`lastSentAt`) lives alongside the code but
 *     is NEVER cleared when the code is consumed, expires, or is locked out.
 *     Wiping the whole record on those paths (the previous behaviour) let a
 *     caller reset the hourly cap by simply exhausting attempts, so the cap
 *     was bypassable; the clear-code path below deliberately preserves it.
 *
 * All timestamps in a record are epoch-millisecond NUMBERS (not Firestore
 * `Timestamp`s): the records are internal, denied to every client by the
 * security rules, and read only by these callables — so numbers keep this
 * module dependency-free and trivially testable.
 */

const {createHmac, randomBytes, randomInt, timingSafeEqual} =
  require("node:crypto");

/** Sensible defaults; ../index.js passes an explicit config built from its
 * own tunables so the two stay in lock-step. */
const DEFAULT_CONFIG = {
  codeLength: 6,
  ttlMs: 10 * 60 * 1000,
  maxAttempts: 5,
  cooldownMs: 60 * 1000,
  maxSendsPerHour: 5,
  hourMs: 60 * 60 * 1000,
};

/**
 * A cryptographically-uniform `length`-digit string (leading zeros kept).
 * @param {number} length
 * @return {string}
 */
const generateCode = (length = DEFAULT_CONFIG.codeLength) => {
  let out = "";
  for (let i = 0; i < length; i++) out += randomInt(0, 10).toString();
  return out;
};

/**
 * HMAC-SHA256(pepper, `${salt}:${code}`) as hex. Keyed by the server secret.
 * @param {string} code
 * @param {string} salt
 * @param {string} pepper
 * @return {string}
 */
const hashCode = (code, salt, pepper) =>
  createHmac("sha256", pepper).update(`${salt}:${code}`).digest("hex");

/**
 * Constant-time comparison of two hex digests.
 * @param {string} a
 * @param {string} b
 * @return {boolean}
 */
const digestsEqual = (a, b) => {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const ba = Buffer.from(a, "hex");
  const bb = Buffer.from(b, "hex");
  if (ba.length !== bb.length || ba.length === 0) return false;
  return timingSafeEqual(ba, bb);
};

/**
 * The patch that clears the ACTIVE-CODE fields while leaving the throttle
 * accounting (`windowStartAt`/`sendCount`/`lastSentAt`) untouched. Applied on
 * verify success, expiry, and attempt lock-out.
 * @return {!Object}
 */
const clearCodePatch = () => ({
  codeHash: null,
  salt: null,
  attempts: 0,
  expiresAt: null,
  createdAt: null,
});

/**
 * Decides whether to send a fresh code, report a cooldown, or reject for the
 * hourly cap — purely, from the existing record and the current time.
 *
 * @param {{existing: ?Object, nowMs: number, pepper: string,
 *   config: (!Object|undefined)}} args
 * @return {{kind: string, code: (string|undefined),
 *   doc: (!Object|undefined), retryAfterSeconds: (number|undefined)}}
 *   kind is one of: "send" (write `doc`, then email `code`), "cooldown", or
 *   "capped" (both carry `retryAfterSeconds`).
 */
const decideSend = ({existing, nowMs, pepper, config = DEFAULT_CONFIG}) => {
  const {ttlMs, cooldownMs, maxSendsPerHour, hourMs, codeLength} = config;

  let windowStartMs = nowMs;
  let sendCount = 0;

  if (existing) {
    const startedAt = existing.windowStartAt;
    if (typeof startedAt === "number" && nowMs - startedAt < hourMs) {
      // Still inside the rolling 1h window — carry the count forward.
      windowStartMs = startedAt;
      sendCount = typeof existing.sendCount === "number" ?
        existing.sendCount : 0;
      if (sendCount >= maxSendsPerHour) {
        return {
          kind: "capped",
          retryAfterSeconds: Math.ceil((startedAt + hourMs - nowMs) / 1000),
        };
      }
    } // else: window elapsed → reset (windowStartMs = nowMs, sendCount = 0).

    // Resend cooldown: an active, still-valid code was sent very recently.
    const codeStillValid = !!existing.codeHash &&
      typeof existing.expiresAt === "number" && existing.expiresAt > nowMs;
    if (codeStillValid && typeof existing.lastSentAt === "number") {
      const sinceLastSent = nowMs - existing.lastSentAt;
      if (sinceLastSent < cooldownMs) {
        return {
          kind: "cooldown",
          retryAfterSeconds: Math.ceil((cooldownMs - sinceLastSent) / 1000),
        };
      }
    }
  }

  const code = generateCode(codeLength);
  const salt = randomBytes(16).toString("hex");
  const doc = {
    // Active code.
    codeHash: hashCode(code, salt, pepper),
    salt,
    attempts: 0,
    createdAt: nowMs,
    expiresAt: nowMs + ttlMs,
    // Throttle accounting (preserved across code clears).
    lastSentAt: nowMs,
    sendCount: sendCount + 1,
    windowStartAt: windowStartMs,
  };
  return {kind: "send", code, doc};
};

/**
 * Decides the outcome of a verification attempt — purely, from the existing
 * record, the submitted code, and the current time.
 *
 * @param {{existing: ?Object, code: string, nowMs: number, pepper: string,
 *   config: (!Object|undefined)}} args
 * @return {{kind: string, patch: (!Object|undefined),
 *   attemptsRemaining: (number|undefined)}}
 *   kind is one of: "none" (no active code), "expired", "exhausted",
 *   "invalid" (carries `attemptsRemaining`), or "ok". Every kind except
 *   "none" carries a `patch` to apply inside the caller's transaction.
 */
const decideVerify = ({
  existing, code, nowMs, pepper, config = DEFAULT_CONFIG,
}) => {
  const {maxAttempts} = config;

  if (!existing || !existing.codeHash) return {kind: "none"};

  if (typeof existing.expiresAt === "number" && existing.expiresAt <= nowMs) {
    return {kind: "expired", patch: clearCodePatch()};
  }

  const attempts = typeof existing.attempts === "number" ?
    existing.attempts : 0;
  if (attempts >= maxAttempts) {
    return {kind: "exhausted", patch: clearCodePatch()};
  }

  const candidate = hashCode(code, existing.salt, pepper);
  if (!digestsEqual(candidate, existing.codeHash)) {
    const next = attempts + 1;
    if (next >= maxAttempts) {
      return {kind: "exhausted", patch: clearCodePatch()};
    }
    return {
      kind: "invalid",
      attemptsRemaining: maxAttempts - next,
      patch: {attempts: next},
    };
  }

  // Correct → consume (single-use), preserving the throttle accounting.
  return {kind: "ok", patch: clearCodePatch()};
};

module.exports = {
  DEFAULT_CONFIG,
  generateCode,
  hashCode,
  digestsEqual,
  clearCodePatch,
  decideSend,
  decideVerify,
};
