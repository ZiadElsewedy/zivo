/**
 * ZIVO — authentication activity bookkeeping (server side).
 *
 * Two Firestore locations hold each account's auth metadata:
 *
 *   users/{uid}/auth/account          — a single always-current summary doc
 *       (createdAt, registeredVia, lastSignInAt/Via, signInCount,
 *       emailVerifiedAt, emailLastSentAt, lastPasswordChangeAt, …)
 *   users/{uid}/authEvents/{auto-id}  — an append-only fact log
 *       (accountCreated | signIn | signOut | emailOtpSent | emailVerified |
 *        passwordChanged, each with a server-clock occurredAt)
 *
 * The CLIENT writes the session-flavoured entries it is the only witness to
 * (sign-ins with their provider/platform). This module writes the entries
 * that must not be forgeable: when a verification email was actually sent
 * and when an address actually became verified — both flow through these
 * callables' hands only. The Admin SDK bypasses security rules; the rules
 * additionally forbid clients from ever updating/deleting event docs.
 *
 * Kept free of any `firebase-admin` import so it stays unit-testable under
 * plain `node --test` (mirroring ./ai/gateway.js): plain `Date` values are
 * accepted by the Admin SDK and persisted as Firestore timestamps.
 */

/** Bumped when either location's shape changes; lets readers branch safely. */
const SCHEMA_VERSION = 1;

/**
 * The account summary doc ref for [uid].
 * @param {!Firestore} db
 * @param {string} uid
 * @return {!DocumentReference}
 */
const accountRef = (db, uid) =>
  db.collection("users").doc(uid).collection("auth").doc("account");

/**
 * Appends one event to the user's auth-event log. Never throws on its own —
 * callers wrap in try/catch so bookkeeping stays non-fatal.
 * @param {!Firestore} db
 * @param {string} uid
 * @param {string} type One of AuthEventType's wire ids.
 * @param {{provider?: string}=} extra Optional fields (provider).
 * @return {!Promise<!WriteResult>}
 */
const recordAuthEvent = (db, uid, type, extra = {}) =>
  db.collection("users").doc(uid).collection("authEvents").add({
    schemaVersion: SCHEMA_VERSION,
    type,
    ...(extra.provider ? {provider: extra.provider} : {}),
    occurredAt: new Date(),
  });

/**
 * Records that a verification code was actually emailed: stamps
 * `emailLastSentAt` on the summary and appends an `emailOtpSent` event.
 * Called only after Resend accepted the message.
 * @param {!Firestore} db
 * @param {string} uid
 * @return {!Promise<void>}
 */
const markEmailSent = async (db, uid) => {
  const now = new Date();
  await Promise.all([
    recordAuthEvent(db, uid, "emailOtpSent"),
    accountRef(db, uid).set({
      schemaVersion: SCHEMA_VERSION,
      emailLastSentAt: now,
      updatedAt: now,
    }, {merge: true}),
  ]);
};

/**
 * Records that the email became verified: stamps `emailVerifiedAt` on the
 * summary and appends an `emailVerified` event. Called only after
 * `updateUser({emailVerified: true})` succeeded.
 * @param {!Firestore} db
 * @param {string} uid
 * @return {!Promise<void>}
 */
const markEmailVerified = async (db, uid) => {
  const now = new Date();
  await Promise.all([
    recordAuthEvent(db, uid, "emailVerified"),
    accountRef(db, uid).set({
      schemaVersion: SCHEMA_VERSION,
      emailVerifiedAt: now,
      updatedAt: now,
    }, {merge: true}),
  ]);
};

module.exports = {SCHEMA_VERSION, recordAuthEvent, markEmailSent, markEmailVerified};
