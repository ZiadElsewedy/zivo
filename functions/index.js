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
const logger = require("firebase-functions/logger");
const {Resend} = require("resend");
const Anthropic = require("@anthropic-ai/sdk");
const {
  runAiTurn,
  confirmAction,
  cancelAction,
  GatewayError,
} = require("./ai/gateway");
const {extractWorkoutPlan} = require("./ai/workout_import");
const {FirestoreStore} = require("./ai/store");
const {AnthropicProvider} = require("./ai/providers/anthropic_provider");
const {ProviderRegistry} = require("./ai/providers/registry");
const router = require("./ai/routing/router");

initializeApp();
const db = getFirestore();

setGlobalOptions({maxInstances: 10});

// --- Secrets (set via `firebase functions:secrets:set ...`) ----------------
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");
// A strong random string that keys the OTP HMAC. Not stored with the code, so
// it defeats offline brute force of the small 6-digit space if the DB leaks.
const OTP_PEPPER = defineSecret("OTP_PEPPER");
// The Anthropic API key backing the `aiChat` gateway (ADR-001). Read only
// via `.value()` inside the handler below — never hardcoded or logged.
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

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

// --- aiChat ------------------------------------------------------------

/**
 * `GatewayError` codes are already gRPC-style (`"invalid-argument"`, etc),
 * matching `HttpsError`'s accepted `code` values directly.
 * @param {!Error} err
 * @return {!HttpsError}
 */
const toHttpsError = (err) => {
  if (err instanceof GatewayError) return new HttpsError(err.code, err.message);
  console.error("aiChat: unhandled error", err);
  return new HttpsError(
      "internal", "Ask couldn't answer that. Please try again.");
};

/**
 * Builds a `ProviderRegistry` backed by the real Anthropic client, the one
 * real `AiProvider` today (`./ai/providers/anthropic_provider.js`). A second
 * real provider is a new adapter file plus one more `.register()` call here —
 * `./ai/routing/router.js`'s capability table is the only other place that
 * needs to know about it.
 * @param {!Anthropic} anthropic
 * @return {!ProviderRegistry}
 */
function buildProviderRegistry(anthropic) {
  return new ProviderRegistry().register("anthropic", new AnthropicProvider(anthropic));
}

/**
 * An `AiProvider`-shaped object whose `generate` resolves `capability` via
 * `./ai/routing/router.js` on every call — including the router's
 * fallback-on-error policy, transparently to `./ai/gateway.js`/
 * `./ai/workout_import.js`, which only ever see a single `provider.generate`.
 * @param {!ProviderRegistry} registry
 * @param {string} capability
 * @return {!Object}
 */
function providerForCapability(registry, capability) {
  return {
    generate: (normalizedRequest, opts) =>
      router.generate(registry, capability, normalizedRequest, opts),
  };
}

/**
 * The "Ask" AI assistant gateway (ADR-001): a read-only, tool-mediated
 * Claude conversation over the user's own ZIVO data. All orchestration
 * (history windowing, the tool loop, cost/iteration ceilings, usage
 * logging) lives in `./ai/gateway.js`/`./ai/tools.js` so it is unit-testable
 * without the network or the emulator; this handler only wires the real
 * Anthropic client, provider/routing seam, and Firestore store, and maps
 * errors.
 */
exports.aiChat = onCall(
    {
      secrets: [ANTHROPIC_API_KEY],
      region: "us-central1",
      // M9 Phase 4: attest that calls come from a genuine app instance (the
      // client activates App Check in `lib/main.dart`). MUST NOT be deployed
      // until App Check providers are registered in the Firebase Console for
      // this project, or the owner's own device is locked out of Ask.
      enforceAppCheck: true,
    },
    async (request, response) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in to use Ask.");
      }

      const data = request.data || {};
      const conversationId = (data.conversationId || "").toString();
      const message = (data.message || "").toString();

      const anthropic = new Anthropic({apiKey: ANTHROPIC_API_KEY.value()});
      const registry = buildProviderRegistry(anthropic);
      const store = new FirestoreStore(db);

      // When the client opts into streaming (`httpsCallable.stream()`), forward
      // the gateway's phase/delta events as chunks and stream the model. A
      // plain `.call()` sets `acceptsStreaming` false, so the turn runs exactly
      // as before — buffered, no events, no per-token work. The final return
      // value is delivered to both call styles either way.
      const streaming = request.acceptsStreaming === true && !!response;

      try {
        return await runAiTurn({
          store,
          provider: providerForCapability(registry, "chat"),
          model: router.resolve("chat").model,
          stream: streaming,
          onEvent: streaming ? (event) => response.sendChunk(event) : undefined,
          uid: auth.uid,
          conversationId,
          message,
          now: () => new Date(),
        });
      } catch (err) {
        throw toHttpsError(err);
      }
    },
);

// --- aiConfirmAction / aiCancelAction (ADR-003 V2) -------------------------

// These WRITE user data, so — like `aiChat` — they enforce App Check
// (`enforceAppCheck: true`). CRITICAL DEPLOY ORDERING: register App Check
// providers in the Firebase Console for this project FIRST, then deploy the
// functions. Deploying enforcement before the Console providers exist locks the
// owner's own device out of all three AI callables.

/**
 * Executes a user-confirmed pending action (ADR-003): performs the proposed
 * Firestore write server-side, keyed by `actionId` (idempotent). The write
 * logic lives in `./ai/gateway.js` (offline-testable); this handler only wires
 * the store and maps errors.
 */
exports.aiConfirmAction = onCall(
    {region: "us-central1", enforceAppCheck: true}, async (request) => {
      const auth = request.auth;
      if (!auth) throw new HttpsError("unauthenticated", "Sign in to use Ask.");

      const data = request.data || {};
      const conversationId = (data.conversationId || "").toString();
      const actionId = (data.actionId || "").toString();

      try {
        return await confirmAction({
          store: new FirestoreStore(db),
          uid: auth.uid,
          conversationId,
          actionId,
          now: () => new Date(),
        });
      } catch (err) {
        throw toHttpsError(err);
      }
    });

/**
 * Cancels a pending action (ADR-003): marks it cancelled and appends a note.
 * Never writes an entity.
 */
exports.aiCancelAction = onCall(
    {region: "us-central1", enforceAppCheck: true}, async (request) => {
      const auth = request.auth;
      if (!auth) throw new HttpsError("unauthenticated", "Sign in to use Ask.");

      const data = request.data || {};
      const conversationId = (data.conversationId || "").toString();
      const actionId = (data.actionId || "").toString();

      try {
        return await cancelAction({
          store: new FirestoreStore(db),
          uid: auth.uid,
          conversationId,
          actionId,
          now: () => new Date(),
        });
      } catch (err) {
        throw toHttpsError(err);
      }
    });

// --- aiImportWorkoutPlan (WORKOUT_SYSTEM.md §3.4, Phase 6) -----------------

// ADR-002 guardrail: reject an oversized upload before it reaches the model.
// Base64 runs ~4/3 the raw byte size, so this ~14M-char cap covers roughly a
// 10.5MB raw PDF — well short of ADR-002's ~32MB ceiling (that number is
// sized for messier scanned/multi-page documents; a 32MB cap here would need
// ~43M base64 chars, which risks the callable transport's own payload
// limit). Workout PDFs are typically a few pages, so this leaves generous
// headroom for the real target while failing fast, with a clear message,
// well before any transport-level rejection.
const MAX_PDF_BASE64_CHARS = 14 * 1024 * 1024;

/**
 * Extracts a proposed workout split from an uploaded PDF (WORKOUT_SYSTEM.md
 * §3.4): one Claude call, no Firestore write. The client reviews/edits the
 * result (reusing `WorkoutPlanEditPage` in `asSplit` mode) and saves it
 * itself via `saveSplit` — that review screen is the "human confirms before
 * it becomes real" gate, so there is nothing here to confirm or cancel.
 *
 * Deliberately UNauthenticated: this call reads and extracts a PDF, nothing
 * more — it never touches Firestore, so there's no user data to protect at
 * this step. `enforceAppCheck` is the abuse control here (blocks scripted
 * callers, not signed-out humans); auth is required later, at save time
 * (`saveSplit`/`savePlan`, gated client-side and by Firestore's owner-only
 * rules), where a workout plan actually gets written to an account.
 */
exports.aiImportWorkoutPlan = onCall(
    {
      secrets: [ANTHROPIC_API_KEY],
      region: "us-central1",
      enforceAppCheck: true,
      // A single Claude call reading a whole PDF (native document input,
      // every page) can run well past the platform's 60s default — unlike
      // aiChat's short per-turn tool calls, there's no streaming/chunking
      // here to keep each round-trip small.
      timeoutSeconds: 180,
    },
    async (request) => {
      const data = request.data || {};
      const pdfBase64 = (data.pdfBase64 || "").toString();
      if (pdfBase64.length > MAX_PDF_BASE64_CHARS) {
        throw new HttpsError(
            "invalid-argument", "That PDF is too large to import.");
      }

      const anthropic = new Anthropic({apiKey: ANTHROPIC_API_KEY.value()});
      const registry = buildProviderRegistry(anthropic);
      // base64 runs ~4/3 the raw byte size — approximate, but enough to spot
      // "why did this reject" patterns (e.g. a suspiciously tiny upload).
      const approxPdfBytes = Math.round(pdfBase64.length * 3 / 4);

      try {
        const result = await extractWorkoutPlan({
          provider: providerForCapability(registry, "workout_import"),
          model: router.resolve("workout_import").model,
          pdfBase64,
          logEvent: (event) => logger.info("aiImportWorkoutPlan", {
            approxPdfBytes,
            ...event,
          }),
        });
        return result;
      } catch (err) {
        logger.info("aiImportWorkoutPlan", {
          approxPdfBytes,
          stage: "error",
          message: err && err.message,
        });
        throw toHttpsError(err);
      }
    },
);
