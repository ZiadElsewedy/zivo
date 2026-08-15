/**
 * ZIVO — email OTP verification backend.
 *
 * Two callable functions gate email/password sign-ups behind a 6-digit code:
 *
 *   sendEmailOtp()       → generates, hashes, stores, and emails a fresh code
 *   verifyEmailOtp(code) → checks the code and flips the user's emailVerified
 *
 * Security posture (all enforced here — the client is never trusted):
 *   • The code is generated with a CSPRNG and NEVER stored or logged in
 *     plaintext. Firestore holds only an HMAC-SHA256 digest keyed by a server
 *     secret (OTP_PEPPER) plus a per-code random salt, so a database leak does
 *     not expose codes even against offline brute force.
 *   • Single-use: the record is deleted the moment a code verifies.
 *   • Expiry: codes are valid for OTP_TTL_MINUTES.
 *   • Attempt cap: MAX_ATTEMPTS wrong guesses invalidate the code.
 *   • Resend cooldown (RESEND_COOLDOWN_SECONDS) and an hourly send cap
 *     (MAX_SENDS_PER_HOUR) throttle abuse.
 *   • The emailOtps/{uid} collection is locked to clients by Firestore rules;
 *     only this Admin SDK code reads or writes it.
 */

const {createHmac, randomBytes, randomInt, timingSafeEqual} =
  require("node:crypto");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions");
const {defineSecret} = require("firebase-functions/params");
const {Resend} = require("resend");

initializeApp();
const db = getFirestore();

setGlobalOptions({maxInstances: 10});

// --- Secrets (set via `firebase functions:secrets:set ...`) ----------------
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");
// A strong random string that keys the OTP HMAC. Not stored with the code, so
// it defeats offline brute force of the small 6-digit space if the DB leaks.
const OTP_PEPPER = defineSecret("OTP_PEPPER");

// --- Tunables ---------------------------------------------------------------
const OTP_TTL_MINUTES = 10;
const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_SECONDS = 60;
const MAX_SENDS_PER_HOUR = 5;
const CODE_LENGTH = 6;
const HOUR_MS = 60 * 60 * 1000;

// The verified "From" identity on your Resend account. `zzivo.com` is verified
// in Resend (DNS via Cloudflare), so we can send to any recipient — not just
// the account owner, which was the limit of the shared onboarding sender.
const EMAIL_FROM = "ZIVO <no-reply@zzivo.com>";

const COLLECTION = "emailOtps";

/**
 * A cryptographically-uniform CODE_LENGTH-digit string (leading zeros kept).
 * @return {string}
 */
const generateCode = () => {
  let out = "";
  for (let i = 0; i < CODE_LENGTH; i++) out += randomInt(0, 10).toString();
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
  const ba = Buffer.from(a, "hex");
  const bb = Buffer.from(b, "hex");
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
};

/**
 * The branded ZIVO verification email.
 * @param {string} code
 * @return {{subject: string, html: string, text: string}}
 */
const brandedEmail = (code) => {
  const spaced = code.split("").join("&nbsp;&nbsp;");
  return {
    subject: `${code} is your ZIVO verification code`,
    text:
      `Your ZIVO verification code is ${code}.\n\n` +
      `It expires in ${OTP_TTL_MINUTES} minutes. ` +
      `If you didn't request it, you can ignore this email.`,
    html: `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#F3ECE3;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3ECE3;padding:40px 0;">
      <tr>
        <td align="center">
          <table role="presentation" width="440" cellpadding="0" cellspacing="0" style="max-width:440px;width:100%;background:#FBF7F1;border-radius:20px;border:1px solid #E7DccE;overflow:hidden;">
            <tr>
              <td style="padding:36px 40px 8px 40px;">
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:22px;font-weight:700;letter-spacing:2px;color:#1E1A16;">ZIVO</div>
              </td>
            </tr>
            <tr>
              <td style="padding:12px 40px 0 40px;">
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:17px;font-weight:600;color:#1E1A16;">Verify your email</div>
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:14px;line-height:22px;color:#6B6157;margin-top:6px;">Enter this code in the app to finish setting up your space.</div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 40px 8px 40px;">
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Menlo,monospace;font-size:34px;font-weight:700;letter-spacing:8px;color:#C2410C;background:#F6EDE3;border:1px solid #EAD9C6;border-radius:14px;text-align:center;padding:18px 0;">${spaced}</div>
              </td>
            </tr>
            <tr>
              <td style="padding:8px 40px 36px 40px;">
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12.5px;line-height:20px;color:#9A8F82;">This code expires in ${OTP_TTL_MINUTES} minutes and can be used once. If you didn't request it, you can safely ignore this email.</div>
              </td>
            </tr>
          </table>
          <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:11px;color:#B4A99B;margin-top:18px;">ZIVO · your whole day, in one place</div>
        </td>
      </tr>
    </table>
  </body>
</html>`,
  };
};

// --- sendEmailOtp -----------------------------------------------------------

exports.sendEmailOtp = onCall(
    {secrets: [RESEND_API_KEY, OTP_PEPPER], region: "us-central1"},
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError(
            "unauthenticated", "Sign in before requesting a code.");
      }
      const uid = auth.uid;
      const email = auth.token.email;
      if (!email) {
        throw new HttpsError(
            "failed-precondition",
            "No email is associated with this account.");
      }
      // Already verified (e.g. a stale client): nothing to do.
      if (auth.token.email_verified === true) {
        return {status: "already-verified"};
      }

      const pepper = OTP_PEPPER.value();
      const ref = db.collection(COLLECTION).doc(uid);
      const now = Date.now();

      // Reserve/decide inside a transaction; the plaintext code only ever lives
      // in this function's memory and is returned for the email send below.
      const decision = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const existing = snap.exists ? snap.data() : undefined;

        // Hourly send cap (rolling 1h window).
        let sendCount = 0;
        let windowStartMs = now;
        if (existing) {
          windowStartMs = existing.windowStartAt.toMillis();
          if (now - windowStartMs < HOUR_MS) {
            sendCount = existing.sendCount;
            if (sendCount >= MAX_SENDS_PER_HOUR) {
              const retryAfterSeconds = Math.ceil(
                  (windowStartMs + HOUR_MS - now) / 1000);
              throw new HttpsError(
                  "resource-exhausted",
                  "Too many codes requested. Please try again later.",
                  {retryAfterSeconds});
            }
          } else {
            windowStartMs = now; // window elapsed → reset
          }

          // Resend cooldown: a still-valid code was sent very recently.
          const sinceLastSent = now - existing.lastSentAt.toMillis();
          const codeStillValid = existing.expiresAt.toMillis() > now;
          const cooldownMs = RESEND_COOLDOWN_SECONDS * 1000;
          if (codeStillValid && sinceLastSent < cooldownMs) {
            const retryAfterSeconds = Math.ceil(
                (cooldownMs - sinceLastSent) / 1000);
            return {action: "cooldown", retryAfterSeconds};
          }
        }

        const code = generateCode();
        const salt = randomBytes(16).toString("hex");
        tx.set(ref, {
          codeHash: hashCode(code, salt, pepper),
          salt,
          attempts: 0,
          createdAt: Timestamp.fromMillis(now),
          expiresAt: Timestamp.fromMillis(now + OTP_TTL_MINUTES * 60 * 1000),
          lastSentAt: Timestamp.fromMillis(now),
          sendCount: sendCount + 1,
          windowStartAt: Timestamp.fromMillis(windowStartMs),
        });
        return {action: "send", code};
      });

      if (decision.action === "cooldown") {
        return {
          status: "cooldown",
          retryAfterSeconds: decision.retryAfterSeconds,
        };
      }

      // Send the branded email. If this fails, drop the record so the user can
      // retry immediately rather than being stuck behind the cooldown.
      try {
        const resend = new Resend(RESEND_API_KEY.value());
        const {subject, html, text} = brandedEmail(decision.code);
        const result = await resend.emails.send({
          from: EMAIL_FROM,
          to: email,
          subject,
          html,
          text,
        });
        if (result.error) throw new Error(result.error.message);
      } catch (err) {
        await ref.delete().catch(() => undefined);
        console.error("sendEmailOtp: email delivery failed", err.message);
        throw new HttpsError(
            "internal", "Couldn't send the code. Please try again.");
      }

      return {
        status: "sent",
        cooldownSeconds: RESEND_COOLDOWN_SECONDS,
        expiresInSeconds: OTP_TTL_MINUTES * 60,
      };
    },
);

// --- verifyEmailOtp ---------------------------------------------------------

exports.verifyEmailOtp = onCall(
    {secrets: [OTP_PEPPER], region: "us-central1"},
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in before verifying.");
      }
      const uid = auth.uid;

      const code = ((request.data && request.data.code) || "").toString();
      if (!/^\d{6}$/.test(code)) {
        throw new HttpsError("invalid-argument", "Enter the 6-digit code.");
      }

      const pepper = OTP_PEPPER.value();
      const ref = db.collection(COLLECTION).doc(uid);

      // Verify + single-use consume atomically so parallel submits can't both
      // win and the attempt counter can't be raced.
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new HttpsError(
              "failed-precondition", "No active code. Request a new one.");
        }
        const doc = snap.data();

        if (doc.expiresAt.toMillis() <= Date.now()) {
          tx.delete(ref);
          throw new HttpsError(
              "failed-precondition",
              "That code has expired. Request a new one.");
        }
        if (doc.attempts >= MAX_ATTEMPTS) {
          tx.delete(ref);
          throw new HttpsError(
              "resource-exhausted", "Too many attempts. Request a new code.");
        }

        const candidate = hashCode(code, doc.salt, pepper);
        if (!digestsEqual(candidate, doc.codeHash)) {
          const attempts = doc.attempts + 1;
          if (attempts >= MAX_ATTEMPTS) {
            tx.delete(ref);
            throw new HttpsError(
                "resource-exhausted", "Too many attempts. Request a new code.");
          }
          tx.update(ref, {attempts});
          throw new HttpsError("invalid-argument", "That code isn't right.", {
            attemptsRemaining: MAX_ATTEMPTS - attempts,
          });
        }

        // Correct → consume (single-use).
        tx.delete(ref);
      });

      // Flip the canonical verified flag. The client force-refreshes its token
      // afterwards so the auth gate advances.
      await getAuth().updateUser(uid, {emailVerified: true});

      return {status: "verified"};
    },
);
