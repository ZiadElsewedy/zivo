/**
 * Unit tests for ./auth/otp.js — the pure OTP decision core shared by the
 * email-verification and password-reset callables.
 *
 * Run with: node --test auth/otp.test.js  (from functions/).
 *
 * These exercise the security-critical logic directly, with no Firestore: code
 * generation, keyed hashing + constant-time compare, the send throttle
 * (cooldown + hourly cap), the verify state machine (expiry, attempt cap,
 * single-use consume), and — the regression that motivated this module — that
 * exhausting attempts or consuming a code NEVER resets the hourly send cap.
 */

const {test} = require("node:test");
const assert = require("node:assert/strict");

const {
  generateCode,
  hashCode,
  digestsEqual,
  clearCodePatch,
  decideSend,
  decideVerify,
} = require("./otp");

const PEPPER = "unit-test-pepper";
const CONFIG = {
  codeLength: 6,
  ttlMs: 10 * 60 * 1000,
  maxAttempts: 5,
  cooldownMs: 60 * 1000,
  maxSendsPerHour: 5,
  hourMs: 60 * 60 * 1000,
};
const NOW = 1_700_000_000_000; // fixed clock

/** Merge a verify patch onto a record the way tx.update would. */
const applyPatch = (doc, patch) => ({...doc, ...patch});

// --- generateCode / hashCode / digestsEqual --------------------------------

test("generateCode returns a code of the requested length, digits only", () => {
  for (let i = 0; i < 200; i++) {
    const code = generateCode(6);
    assert.equal(code.length, 6);
    assert.match(code, /^\d{6}$/);
  }
});

test("generateCode can produce leading zeros (kept as string)", () => {
  let sawLeadingZero = false;
  for (let i = 0; i < 2000 && !sawLeadingZero; i++) {
    if (generateCode(6).startsWith("0")) sawLeadingZero = true;
  }
  assert.ok(sawLeadingZero, "expected at least one leading-zero code");
});

test("hashCode is deterministic and keyed by code, salt, and pepper", () => {
  const h = hashCode("123456", "salt", PEPPER);
  assert.equal(h, hashCode("123456", "salt", PEPPER));
  assert.notEqual(h, hashCode("123457", "salt", PEPPER)); // code
  assert.notEqual(h, hashCode("123456", "salt2", PEPPER)); // salt
  assert.notEqual(h, hashCode("123456", "salt", "other")); // pepper
  assert.match(h, /^[0-9a-f]{64}$/); // SHA-256 hex
});

test("digestsEqual is true for equal digests, false otherwise", () => {
  const a = hashCode("111111", "s", PEPPER);
  assert.equal(digestsEqual(a, a), true);
  assert.equal(digestsEqual(a, hashCode("222222", "s", PEPPER)), false);
  assert.equal(digestsEqual(a, ""), false); // length mismatch
  assert.equal(digestsEqual("", ""), false); // empty
  assert.equal(digestsEqual(a, null), false); // non-string
});

// --- decideSend: first send -------------------------------------------------

test("decideSend with no existing record issues a fresh code", () => {
  const d = decideSend({existing: undefined, nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "send");
  assert.match(d.code, /^\d{6}$/);
  assert.equal(d.doc.sendCount, 1);
  assert.equal(d.doc.windowStartAt, NOW);
  assert.equal(d.doc.lastSentAt, NOW);
  assert.equal(d.doc.attempts, 0);
  assert.equal(d.doc.expiresAt, NOW + CONFIG.ttlMs);
  // The stored digest matches the returned plaintext under the same salt.
  assert.equal(d.doc.codeHash, hashCode(d.code, d.doc.salt, PEPPER));
});

// --- decideSend: cooldown ---------------------------------------------------

test("decideSend reports a cooldown for a still-valid code sent recently", () => {
  const existing = {
    codeHash: hashCode("111111", "s", PEPPER),
    salt: "s",
    attempts: 0,
    expiresAt: NOW + 5 * 60 * 1000,
    lastSentAt: NOW - 30 * 1000, // 30s ago, cooldown is 60s
    sendCount: 1,
    windowStartAt: NOW - 30 * 1000,
  };
  const d = decideSend({existing, nowMs: NOW, pepper: PEPPER, config: CONFIG});
  assert.equal(d.kind, "cooldown");
  assert.equal(d.retryAfterSeconds, 30);
});

test("decideSend issues again once the cooldown has elapsed", () => {
  const existing = {
    codeHash: hashCode("111111", "s", PEPPER),
    salt: "s",
    attempts: 0,
    expiresAt: NOW + 5 * 60 * 1000,
    lastSentAt: NOW - 90 * 1000, // 90s ago, past the 60s cooldown
    sendCount: 1,
    windowStartAt: NOW - 90 * 1000,
  };
  const d = decideSend({existing, nowMs: NOW, pepper: PEPPER, config: CONFIG});
  assert.equal(d.kind, "send");
  assert.equal(d.doc.sendCount, 2);
  assert.equal(d.doc.windowStartAt, existing.windowStartAt); // window preserved
});

// --- decideSend: hourly cap -------------------------------------------------

test("decideSend caps at maxSendsPerHour within the window", () => {
  const existing = {
    codeHash: null, // no active code, so cooldown wouldn't apply anyway
    attempts: 0,
    sendCount: CONFIG.maxSendsPerHour,
    windowStartAt: NOW - 10 * 60 * 1000, // 10 min into the hour
    lastSentAt: NOW - 2 * 60 * 1000,
  };
  const d = decideSend({existing, nowMs: NOW, pepper: PEPPER, config: CONFIG});
  assert.equal(d.kind, "capped");
  assert.equal(d.retryAfterSeconds,
      Math.ceil((existing.windowStartAt + CONFIG.hourMs - NOW) / 1000));
});

test("decideSend resets the window once an hour has elapsed", () => {
  const existing = {
    codeHash: null,
    attempts: 0,
    sendCount: CONFIG.maxSendsPerHour, // was capped...
    windowStartAt: NOW - (CONFIG.hourMs + 1000), // ...but the hour has passed
    lastSentAt: NOW - (CONFIG.hourMs + 1000),
  };
  const d = decideSend({existing, nowMs: NOW, pepper: PEPPER, config: CONFIG});
  assert.equal(d.kind, "send");
  assert.equal(d.doc.sendCount, 1); // fresh window
  assert.equal(d.doc.windowStartAt, NOW);
});

// --- decideVerify: state machine -------------------------------------------

const liveRecord = (code, overrides = {}) => ({
  codeHash: hashCode(code, "s", PEPPER),
  salt: "s",
  attempts: 0,
  expiresAt: NOW + 5 * 60 * 1000,
  createdAt: NOW - 60 * 1000,
  sendCount: 1,
  windowStartAt: NOW - 60 * 1000,
  lastSentAt: NOW - 60 * 1000,
  ...overrides,
});

test("decideVerify returns 'none' when there is no active code", () => {
  assert.equal(decideVerify({existing: undefined, code: "123456", nowMs: NOW,
    pepper: PEPPER, config: CONFIG}).kind, "none");
  assert.equal(decideVerify({existing: {codeHash: null, sendCount: 3},
    code: "123456", nowMs: NOW, pepper: PEPPER, config: CONFIG}).kind, "none");
});

test("decideVerify rejects an expired code and clears it", () => {
  const existing = liveRecord("123456", {expiresAt: NOW - 1});
  const d = decideVerify({existing, code: "123456", nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "expired");
  assert.equal(d.patch.codeHash, null);
});

test("decideVerify counts a wrong code and reports attemptsRemaining", () => {
  const existing = liveRecord("123456", {attempts: 1});
  const d = decideVerify({existing, code: "000000", nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "invalid");
  assert.equal(d.patch.attempts, 2);
  assert.equal(d.attemptsRemaining, CONFIG.maxAttempts - 2);
});

test("decideVerify locks out on the final wrong attempt", () => {
  const existing = liveRecord("123456", {attempts: CONFIG.maxAttempts - 1});
  const d = decideVerify({existing, code: "000000", nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "exhausted");
  assert.equal(d.patch.codeHash, null);
});

test("decideVerify treats an already-maxed record as exhausted", () => {
  const existing = liveRecord("123456", {attempts: CONFIG.maxAttempts});
  const d = decideVerify({existing, code: "123456", nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "exhausted");
});

test("decideVerify accepts the correct code and consumes it", () => {
  const existing = liveRecord("135790");
  const d = decideVerify({existing, code: "135790", nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(d.kind, "ok");
  // Consuming clears the code fields...
  assert.equal(d.patch.codeHash, null);
  assert.equal(d.patch.salt, null);
  assert.equal(d.patch.expiresAt, null);
});

// --- REGRESSION: the throttle survives clearing the code --------------------

test("clearCodePatch leaves the hourly throttle accounting intact", () => {
  const record = liveRecord("123456", {sendCount: 3, windowStartAt: NOW - 5000});
  const cleared = applyPatch(record, clearCodePatch());
  assert.equal(cleared.codeHash, null); // code gone
  assert.equal(cleared.sendCount, 3); // throttle kept
  assert.equal(cleared.windowStartAt, NOW - 5000);
});

test("exhausting attempts does NOT reset the hourly send cap", () => {
  // Send #1..#5 fill the hourly window (sendCount reaches the cap).
  let record = decideSend({existing: undefined, nowMs: NOW, pepper: PEPPER,
    config: CONFIG}).doc;
  for (let i = 2; i <= CONFIG.maxSendsPerHour; i++) {
    // Clear the previous code (as if it was consumed/expired) so cooldown
    // doesn't block, then send again — still within the same hour window.
    record = applyPatch(record, clearCodePatch());
    const d = decideSend({existing: record, nowMs: NOW, pepper: PEPPER,
      config: CONFIG});
    assert.equal(d.kind, "send");
    record = d.doc;
  }
  assert.equal(record.sendCount, CONFIG.maxSendsPerHour);

  // Now blow through the attempt cap on the active code — the OLD bug deleted
  // the whole record here, resetting the throttle.
  const nearLockout = {...record, attempts: CONFIG.maxAttempts - 1};
  const exhausted = decideVerify({existing: nearLockout, code: "000000",
    nowMs: NOW, pepper: PEPPER, config: CONFIG});
  assert.equal(exhausted.kind, "exhausted");
  record = applyPatch(nearLockout, exhausted.patch);

  // A further send must STILL be capped — the bypass is closed.
  const after = decideSend({existing: record, nowMs: NOW, pepper: PEPPER,
    config: CONFIG});
  assert.equal(after.kind, "capped");
});
