/**
 * ZIVO — authentication backend (OTP flows + account deletion).
 *
 * Callables that gate the email/password lifecycle behind a 6-digit code and
 * that tear an account down cleanly:
 *
 *   sendEmailOtp()                              → email a verification code
 *   verifyEmailOtp(code)                        → verify it, flip emailVerified
 *   sendPasswordResetOtp(email)                 → email a reset code (signed out)
 *   resetPasswordWithOtp(email, code, password) → verify it, set the password
 *   deleteAccount()                             → erase all data + the identity
 *
 * The OTP mechanics (CSPRNG code, HMAC-SHA256 digest keyed by the OTP_PEPPER
 * secret + a per-code salt, expiry, single-use, attempt cap, resend cooldown,
 * and an hourly send cap whose accounting survives a code being consumed) live
 * in ./auth/otp.js as PURE, unit-tested decision functions; the callables here
 * only wrap a Firestore transaction around them, send the branded email, and
 * apply the success side-effect. The client is never trusted.
 *
 * Both `emailOtps/{uid}` and `passwordResetOtps/{uid}` are locked to clients by
 * the Firestore rules; only this Admin SDK code reads or writes them.
 */

const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {Resend} = require("resend");
const Anthropic = require("@anthropic-ai/sdk");
const otp = require("./auth/otp");
const {
  markEmailSent,
  markEmailVerified,
  markPasswordChanged,
} = require("./auth/activity");
const {
  runAiTurn,
  confirmAction,
  cancelAction,
  GatewayError,
} = require("./ai/gateway");
const {extractWorkoutPlan} = require("./ai/workout_import");
const {extractDietPlan} = require("./ai/diet_import");
const {deliverWeeklyReport} = require("./ai/coach_report");
const {FirestoreStore} = require("./ai/store");
const {AnthropicProvider} = require("./ai/providers/anthropic_provider");
const {ProviderRegistry} = require("./ai/providers/registry");
const router = require("./ai/routing/router");
const {OpenAI, toFile} = require("openai");
const {GoogleGenAI} = require("@google/genai");
const {transcribeAudio, SpeechError} = require("./ai/speech/gateway");
const {GeminiSpeechProvider} = require("./ai/speech/providers/gemini_speech_provider");
const {OpenAiSpeechProvider} = require("./ai/speech/providers/openai_speech_provider");
const speechRouter = require("./ai/speech/routing/speech_router");

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
// The Google Gemini API key backing the DEFAULT `aiTranscribe` STT route.
// Read only via `.value()` inside the handler below — never hardcoded or
// logged. Speech-to-text is a separate capability from the Anthropic-backed
// chat/workout-import gateways above — see `functions/ai/speech/`.
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
// The OpenAI API key backing the OPTIONAL `aiTranscribe` STT fallback route,
// tried only when the Gemini route errors (see
// `speech/routing/speech_router.js`). Optional so the function can deploy
// Gemini-only without an OpenAI key: it is NOT listed in `aiTranscribe`'s
// `secrets` array below, so it isn't required at deploy time and the handler
// detects its presence at runtime via `process.env`. To ENABLE the fallback:
// (1) `firebase functions:secrets:set OPENAI_API_KEY`, then (2) add
// `OPENAI_API_KEY` to that `secrets` array and redeploy — the handler then
// wires the OpenAI provider automatically.

// --- Tunables ---------------------------------------------------------------
// Kept as a single config object so ./auth/otp.js's pure decision functions
// and these callables share ONE source of truth (and the unit tests can pin
// the exact same numbers).
const OTP_TTL_MINUTES = 10;
const OTP_CONFIG = {
  codeLength: 6,
  ttlMs: OTP_TTL_MINUTES * 60 * 1000,
  maxAttempts: 5,
  cooldownMs: 60 * 1000,
  maxSendsPerHour: 5,
  hourMs: 60 * 60 * 1000,
};

// The verified "From" identity on your Resend account. `zzivo.com` is verified
// in Resend (DNS via Cloudflare), so we can send to any recipient — not just
// the account owner, which was the limit of the shared onboarding sender.
const EMAIL_FROM = "ZIVO <no-reply@zzivo.com>";

// Both OTP stores are Admin-SDK-only (denied to every client by the rules).
const EMAIL_OTP_COLLECTION = "emailOtps";
const PASSWORD_RESET_OTP_COLLECTION = "passwordResetOtps";

/** A well-formed submitted code (exactly the configured number of digits). */
const isWellFormedCode = (code) =>
  new RegExp(`^\\d{${OTP_CONFIG.codeLength}}$`).test(code);

/** A loose "looks like an email" check for the signed-out reset endpoint. */
const isLikelyEmail = (email) =>
  /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);

/** The password policy mirrored from the client's `PasswordPolicy` — enforced
 * again server-side so a crafted request can't set a weak password. */
const isStrongPassword = (p) =>
  typeof p === "string" && p.length >= 8 &&
  /[A-Z]/.test(p) && /[a-z]/.test(p) && /[0-9]/.test(p);

/**
 * The shared branded ZIVO one-time-code email. Only [heading] and [intro]
 * change per purpose (verify vs reset); the wordmark, the spaced code chip,
 * the expiry note, and the footer are identical so both emails read as one
 * family. (The CSPRNG code generation and hashing live in ./auth/otp.js.)
 * @param {{code: string, subject: string, heading: string, intro: string}} a
 * @return {{subject: string, html: string, text: string}}
 */
const otpEmail = ({code, subject, heading, intro}) => {
  const spaced = code.split("").join("&nbsp;&nbsp;");
  return {
    subject,
    text:
      `${intro}\n\nYour code is ${code}.\n\n` +
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
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:17px;font-weight:600;color:#1E1A16;">${heading}</div>
                <div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:14px;line-height:22px;color:#6B6157;margin-top:6px;">${intro}</div>
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

/** The email-verification code email. */
const brandedEmail = (code) => otpEmail({
  code,
  subject: `${code} is your ZIVO verification code`,
  heading: "Verify your email",
  intro: "Enter this code in the app to finish setting up your space.",
});

/** The password-reset code email. */
const passwordResetEmail = (code) => otpEmail({
  code,
  subject: `${code} is your ZIVO password reset code`,
  heading: "Reset your password",
  intro: "Enter this code in the app to set a new password.",
});

// --- shared OTP flow (transaction + email + bookkeeping) --------------------

/**
 * The "send a code" flow shared by both OTP callables: runs the throttle
 * decision (./auth/otp.js) in a transaction — writing only on an actual send —
 * then emails the code and runs optional bookkeeping. The plaintext code never
 * leaves this function beyond the email itself.
 * @param {{ref: !DocumentReference, recipientEmail: string,
 *   buildEmail: function(string): {subject: string, html: string, text: string},
 *   onSent?: function(): !Promise<void>}} args
 * @return {!Promise<!Object>}
 */
const runOtpSend = async ({ref, recipientEmail, buildEmail, onSent}) => {
  const pepper = OTP_PEPPER.value();
  const nowMs = Date.now();

  const decision = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? snap.data() : undefined;
    const d = otp.decideSend({existing, nowMs, pepper, config: OTP_CONFIG});
    if (d.kind === "capped") {
      throw new HttpsError(
          "resource-exhausted",
          "Too many codes requested. Please try again later.",
          {retryAfterSeconds: d.retryAfterSeconds});
    }
    if (d.kind === "send") tx.set(ref, d.doc);
    return d;
  });

  if (decision.kind === "cooldown") {
    return {status: "cooldown", retryAfterSeconds: decision.retryAfterSeconds};
  }

  // Send the branded email. On failure clear only the active code (the hourly
  // throttle accounting stays put) so the user can retry after the cooldown
  // rather than a failed send resetting the rate limit.
  try {
    const resend = new Resend(RESEND_API_KEY.value());
    const {subject, html, text} = buildEmail(decision.code);
    const result = await resend.emails.send({
      from: EMAIL_FROM,
      to: recipientEmail,
      subject,
      html,
      text,
    });
    if (result.error) throw new Error(result.error.message);
  } catch (err) {
    await ref.set(otp.clearCodePatch(), {merge: true}).catch(() => undefined);
    console.error("otp send: email delivery failed", err.message);
    throw new HttpsError(
        "internal", "Couldn't send the code. Please try again.");
  }

  // Bookkeeping must never fail the callable, so swallow its errors.
  if (onSent) {
    try {
      await onSent();
    } catch (err) {
      console.error("otp send: activity recording failed", err.message);
    }
  }

  return {
    status: "sent",
    cooldownSeconds: OTP_CONFIG.cooldownMs / 1000,
    expiresInSeconds: OTP_CONFIG.ttlMs / 1000,
  };
};

/**
 * The "verify a code" flow shared by both OTP callables: runs the verify
 * decision (./auth/otp.js) in a transaction, applying its patch and throwing
 * the mapped HttpsError on any failure; on success runs [onOk] (flip
 * emailVerified / set the new password). The transaction preserves the hourly
 * throttle accounting on every clear path.
 * @param {{ref: !DocumentReference, code: string,
 *   onOk: function(): !Promise<void>}} args
 * @return {!Promise<void>}
 */
const runOtpVerify = async ({ref, code, onOk}) => {
  const pepper = OTP_PEPPER.value();
  const nowMs = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? snap.data() : undefined;
    const d = otp.decideVerify(
        {existing, code, nowMs, pepper, config: OTP_CONFIG});
    switch (d.kind) {
      case "none":
        throw new HttpsError(
            "failed-precondition", "No active code. Request a new one.");
      case "expired":
        tx.update(ref, d.patch);
        throw new HttpsError(
            "failed-precondition", "That code has expired. Request a new one.");
      case "exhausted":
        tx.update(ref, d.patch);
        throw new HttpsError(
            "resource-exhausted", "Too many attempts. Request a new code.");
      case "invalid":
        tx.update(ref, d.patch);
        throw new HttpsError("invalid-argument", "That code isn't right.", {
          attemptsRemaining: d.attemptsRemaining,
        });
      case "ok":
      default:
        tx.update(ref, d.patch);
    }
  });

  await onOk();
};

/**
 * Resolves the uid of a PASSWORD account for [email], or null when there is no
 * such account — WITHOUT revealing which. Used by the signed-out reset flow so
 * the endpoint can't be turned into an account-enumeration oracle. Only
 * accounts that actually have a `password` provider qualify (a Google/Apple-only
 * account has no password to reset, and must not have one added this way).
 * @param {string} email
 * @return {!Promise<?string>}
 */
const resolvePasswordAccountUid = async (email) => {
  try {
    const user = await getAuth().getUserByEmail(email);
    const hasPassword = (user.providerData || [])
        .some((p) => p.providerId === "password");
    return hasPassword ? user.uid : null;
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      console.error("resolvePasswordAccountUid: lookup failed", err.message);
    }
    return null;
  }
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
      // Already verified (e.g. a stale client): nothing to do. The client
      // force-refreshes its token on this status so the auth gate advances.
      if (auth.token.email_verified === true) {
        return {status: "already-verified"};
      }
      return runOtpSend({
        ref: db.collection(EMAIL_OTP_COLLECTION).doc(uid),
        recipientEmail: email,
        buildEmail: brandedEmail,
        onSent: () => markEmailSent(db, uid),
      });
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
      if (!isWellFormedCode(code)) {
        throw new HttpsError("invalid-argument", "Enter the 6-digit code.");
      }

      await runOtpVerify({
        ref: db.collection(EMAIL_OTP_COLLECTION).doc(uid),
        code,
        onOk: async () => {
          // Flip the canonical verified flag. The client force-refreshes its
          // token afterwards so the auth gate advances.
          await getAuth().updateUser(uid, {emailVerified: true});
          // Audit trail: when the address actually became trusted. Non-fatal.
          try {
            await markEmailVerified(db, uid);
          } catch (err) {
            console.error(
                "verifyEmailOtp: activity recording failed", err.message);
          }
        },
      });

      return {status: "verified"};
    },
);

// --- sendPasswordResetOtp ---------------------------------------------------

/**
 * Emails a reset code to a signed-OUT user who owns a password account for the
 * given address. Returns the SAME generic "sent" shape whether or not the
 * account exists (no send happens for a missing/social-only account), so this
 * endpoint can't be used to enumerate accounts. Throttling is identical to
 * email verification, so a real account is capped at the hourly send limit.
 */
exports.sendPasswordResetOtp = onCall(
    {secrets: [RESEND_API_KEY, OTP_PEPPER], region: "us-central1"},
    async (request) => {
      const email =
        ((request.data && request.data.email) || "").toString().trim()
            .toLowerCase();
      if (!isLikelyEmail(email)) {
        throw new HttpsError("invalid-argument", "Enter a valid email address.");
      }

      const uid = await resolvePasswordAccountUid(email);
      if (!uid) {
        // Generic success — no account (or a social-only one) gets no email.
        return {
          status: "sent",
          cooldownSeconds: OTP_CONFIG.cooldownMs / 1000,
          expiresInSeconds: OTP_CONFIG.ttlMs / 1000,
        };
      }

      return runOtpSend({
        ref: db.collection(PASSWORD_RESET_OTP_COLLECTION).doc(uid),
        recipientEmail: email,
        buildEmail: passwordResetEmail,
        // No bookkeeping on send — the reset is recorded on success below.
      });
    },
);

// --- resetPasswordWithOtp ---------------------------------------------------

/**
 * Verifies a reset code and sets the new password (Admin SDK), for a
 * signed-OUT user. The new password is validated against the same policy as
 * the client before the code is consumed, so a weak password can't burn a
 * code. A missing/social-only account resolves to the same "no active code"
 * path a real-but-expired code would, so existence still isn't revealed.
 */
exports.resetPasswordWithOtp = onCall(
    {secrets: [OTP_PEPPER], region: "us-central1"},
    async (request) => {
      const data = request.data || {};
      const email = (data.email || "").toString().trim().toLowerCase();
      const code = (data.code || "").toString();
      const newPassword = (data.newPassword || "").toString();

      if (!isLikelyEmail(email) || !isWellFormedCode(code)) {
        throw new HttpsError(
            "invalid-argument", "Enter the code sent to your email.");
      }
      if (!isStrongPassword(newPassword)) {
        throw new HttpsError(
            "invalid-argument", "Choose a stronger password.",
            {reason: "weakPassword"});
      }

      const uid = await resolvePasswordAccountUid(email);
      if (!uid) {
        throw new HttpsError(
            "failed-precondition", "No active code. Request a new one.");
      }

      await runOtpVerify({
        ref: db.collection(PASSWORD_RESET_OTP_COLLECTION).doc(uid),
        code,
        onOk: async () => {
          // Receiving the code at this address proves ownership, so also mark
          // the email verified — an unverified user who resets shouldn't then
          // be bounced through email verification a second time.
          await getAuth().updateUser(uid, {
            password: newPassword,
            emailVerified: true,
          });
          // Audit trail: when the password actually changed. Non-fatal.
          try {
            await markPasswordChanged(db, uid);
          } catch (err) {
            console.error(
                "resetPasswordWithOtp: activity recording failed", err.message);
          }
        },
      });

      return {status: "reset"};
    },
);

// --- deleteAccount ----------------------------------------------------------

/**
 * Permanently erases the signed-in user: every document under their
 * `users/{uid}` subtree, both OTP records, and finally the auth identity
 * itself. Data-first so a partial failure can never orphan documents beneath a
 * deleted uid. The client reauthenticates before calling this, so a fresh
 * session is required to reach it.
 */
exports.deleteAccount = onCall(
    {region: "us-central1"},
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError(
            "unauthenticated", "Sign in before deleting your account.");
      }
      const uid = auth.uid;
      try {
        await db.recursiveDelete(db.collection("users").doc(uid));
        await Promise.all([
          db.collection(EMAIL_OTP_COLLECTION).doc(uid).delete()
              .catch(() => undefined),
          db.collection(PASSWORD_RESET_OTP_COLLECTION).doc(uid).delete()
              .catch(() => undefined),
        ]);
        await getAuth().deleteUser(uid);
      } catch (err) {
        console.error("deleteAccount: failed", err.message);
        throw new HttpsError(
            "internal", "Couldn't delete your account. Please try again.");
      }
      return {status: "deleted"};
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
    },
    async (request, response) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in to use Ask.");
      }

      const data = request.data || {};
      const conversationId = (data.conversationId || "").toString();
      const message = (data.message || "").toString();
      const responseStyle = (data.responseStyle || "").toString();
      // Client-generated idempotency key — makes a retried turn safe.
      const clientTurnId =
        (data.clientTurnId || "").toString() || undefined;

      const anthropic = new Anthropic({apiKey: ANTHROPIC_API_KEY.value()});
      const registry = buildProviderRegistry(anthropic);
      const store = new FirestoreStore(db);

      // When the client opts into streaming (`httpsCallable.stream()`), forward
      // the gateway's phase/delta events as chunks and stream the model. A
      // plain `.call()` sets `acceptsStreaming` false, so the turn runs exactly
      // as before — buffered, no events, no per-token work. The final return
      // value is delivered to both call styles either way. The flag arrives
      // explicitly in the payload (the transport alone doesn't imply it).
      const streaming =
        request.acceptsStreaming === true ||
        data.acceptsStreaming === true && !!response;

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
          responseStyle,
          clientTurnId,
          now: () => new Date(),
        });
      } catch (err) {
        throw toHttpsError(err);
      }
    },
);

// --- aiConfirmAction / aiCancelAction (ADR-003 V2) -------------------------

// These WRITE user data. Access is gated by Firebase Auth (`request.auth`)
// below and by owner-only Firestore rules; the confirm/cancel logic only ever
// touches the signed-in user's own pending actions.

/**
 * Executes a user-confirmed pending action (ADR-003): performs the proposed
 * Firestore write server-side, keyed by `actionId` (idempotent). The write
 * logic lives in `./ai/gateway.js` (offline-testable); this handler only wires
 * the store and maps errors.
 */
exports.aiConfirmAction = onCall(
    {region: "us-central1"}, async (request) => {
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
    {region: "us-central1"}, async (request) => {
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

// --- aiDeleteConversation ----------------------------------------------

/**
 * Permanently deletes a conversation and everything under it (messages,
 * pendingActions) via `recursiveDelete`. Functions-only: `firestore.rules`
 * lets the client create/rename its own conversations but never delete one
 * (a client delete would orphan the server-written `messages` subcollection
 * it has no permission to remove) — the Admin SDK bypasses rules entirely,
 * which is exactly why this needs its own callable.
 */
exports.aiDeleteConversation = onCall(
    {region: "us-central1"}, async (request) => {
      const auth = request.auth;
      if (!auth) throw new HttpsError("unauthenticated", "Sign in to use Ask.");

      const conversationId = (
        (request.data && request.data.conversationId) || ""
      ).toString();
      if (!conversationId) {
        throw new HttpsError(
            "invalid-argument", "conversationId is required.",
        );
      }

      const ref = db
          .collection("users")
          .doc(auth.uid)
          .collection("aiConversations")
          .doc(conversationId);

      await db.recursiveDelete(ref);
      return {ok: true};
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
 * Requires a signed-in Firebase user: this is an expensive Claude call (a
 * whole-PDF extraction), so it must not be callable anonymously. It writes no
 * Firestore data itself — the extracted split is reviewed and saved later
 * (`saveSplit`/`savePlan`, gated by Firestore's owner-only rules) — but the
 * `request.auth` gate here keeps the paid endpoint behind authentication.
 */
exports.aiImportWorkoutPlan = onCall(
    {
      secrets: [ANTHROPIC_API_KEY],
      region: "us-central1",
      // A single Claude call reading a whole PDF (native document input,
      // every page) can run well past the platform's 60s default — unlike
      // aiChat's short per-turn tool calls, there's no streaming/chunking
      // here to keep each round-trip small.
      timeoutSeconds: 180,
    },
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in to import a plan.");
      }

      const data = request.data || {};
      const pdfBase64 = (data.fileBase64 || data.pdfBase64 || "").toString();
      if (pdfBase64.length > MAX_PDF_BASE64_CHARS) {
        throw new HttpsError(
            "invalid-argument", "That file is too large to import.");
      }
      const mimeType = (data.mimeType || "application/pdf").toString();

      const anthropic = new Anthropic({apiKey: ANTHROPIC_API_KEY.value()});
      const registry = buildProviderRegistry(anthropic);
      // base64 runs ~4/3 the raw byte size — approximate, but enough to spot
      // "why did this reject" patterns (e.g. a suspiciously tiny upload).
      const approxPdfBytes = Math.round(pdfBase64.length * 3 / 4);

      try {
        const result = await extractWorkoutPlan({
          provider: providerForCapability(registry, "workout_import"),
          model: router.resolve("workout_import").model,
          fileBase64: pdfBase64,
          mediaType: mimeType,
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

// --- aiImportDietPlan --------------------------------------------------------

/**
 * Extracts a proposed diet plan from an uploaded PDF, mirroring
 * `aiImportWorkoutPlan` exactly: one Claude call, no Firestore write. The
 * client reviews/edits the result (`DietPlanEditPage`) and saves it itself
 * via `savePlan` — that review screen is the "human confirms before it
 * becomes real" gate, so there is nothing here to confirm or cancel.
 *
 * Requires a signed-in Firebase user for the same reason as
 * `aiImportWorkoutPlan` (an expensive whole-PDF Claude call must not be
 * callable anonymously); it writes no Firestore data itself.
 */
exports.aiImportDietPlan = onCall(
    {
      secrets: [ANTHROPIC_API_KEY],
      region: "us-central1",
      // Same reasoning as aiImportWorkoutPlan: a single whole-PDF read can
      // run well past the platform's 60s default.
      timeoutSeconds: 180,
    },
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in to import a plan.");
      }

      const data = request.data || {};
      const pdfBase64 = (data.fileBase64 || data.pdfBase64 || "").toString();
      if (pdfBase64.length > MAX_PDF_BASE64_CHARS) {
        throw new HttpsError(
            "invalid-argument", "That file is too large to import.");
      }
      const mimeType = (data.mimeType || "application/pdf").toString();

      const anthropic = new Anthropic({apiKey: ANTHROPIC_API_KEY.value()});
      const registry = buildProviderRegistry(anthropic);
      const approxPdfBytes = Math.round(pdfBase64.length * 3 / 4);

      try {
        const result = await extractDietPlan({
          provider: providerForCapability(registry, "diet_import"),
          model: router.resolve("diet_import").model,
          fileBase64: pdfBase64,
          mediaType: mimeType,
          logEvent: (event) => logger.info("aiImportDietPlan", {
            approxPdfBytes,
            ...event,
          }),
        });
        return result;
      } catch (err) {
        logger.info("aiImportDietPlan", {
          approxPdfBytes,
          stage: "error",
          message: err && err.message,
        });
        throw toHttpsError(err);
      }
    },
);

// --- aiTranscribe (speech-to-text, input only) ------------------------------

// A SEPARATE capability from the Anthropic-backed gateways above — never
// routed through `./ai/providers/`/`./ai/routing/router.js`. This only
// returns TEXT for the client to place in the chat composer; it never calls
// the LLM and never speaks text back.

/**
 * Builds a `ProviderRegistry` backed by the two real `SpeechToTextProvider`
 * adapters: Gemini (`./ai/speech/providers/gemini_speech_provider.js`, the
 * default route) and OpenAI (`./ai/speech/providers/openai_speech_provider.js`,
 * the fallback). Which one runs — and in what order — is decided entirely by
 * `./ai/speech/routing/speech_router.js`'s capability table, not here; this
 * only supplies the real network seams. A third STT provider is a new adapter
 * file plus one more `.register()` call here.
 * @param {!GoogleGenAI} genai
 * @param {?OpenAI} openai The OpenAI client, or null when the optional
 *   fallback key isn't configured — then only Gemini is registered and the
 *   router skips the (unregistered) OpenAI route.
 * @return {!ProviderRegistry}
 */
function buildSpeechRegistry(genai, openai) {
  const registry = new ProviderRegistry()
      .register("gemini", new GeminiSpeechProvider({
        transcribe: async ({buffer, mimeType, model, prompt}) => {
          // Gemini transcribes via a multimodal `generateContent` call: the
          // audio rides inline as base64, alongside the adapter's verbatim
          // transcription prompt. Thinking is disabled and temperature pinned
          // to 0 — transcription is deterministic, not a reasoning task.
          const response = await genai.models.generateContent({
            model,
            contents: [{
              role: "user",
              parts: [
                {inlineData: {mimeType, data: buffer.toString("base64")}},
                {text: prompt},
              ],
            }],
            config: {temperature: 0, thinkingConfig: {thinkingBudget: 0}},
          });
          return {text: response.text};
        },
      }));
  if (openai) {
    registry.register("openai", new OpenAiSpeechProvider({
      transcribe: async ({buffer, filename, mimeType, model, language}) => {
        const file = await toFile(buffer, filename, {type: mimeType});
        const params = {file, model, response_format: "json"};
        if (language) params.language = language;
        const result = await openai.audio.transcriptions.create(params);
        return {
          text: result.text,
          language: result.language,
          duration: result.duration,
        };
      },
    }));
  }
  return registry;
}

/**
 * A `SpeechToTextProvider`-shaped object whose `transcribe` resolves
 * `capability` via `./ai/speech/routing/speech_router.js` on every call —
 * including its fallback-on-error policy, transparently to
 * `./ai/speech/gateway.js`, which only ever sees a single
 * `provider.transcribe`.
 * @param {!ProviderRegistry} registry
 * @param {string} capability
 * @return {!Object}
 */
function speechProviderForCapability(registry, capability) {
  return {
    transcribe: (normalizedRequest) =>
      speechRouter.transcribe(registry, capability, normalizedRequest),
  };
}

/**
 * `SpeechError` codes are ZIVO-specific, not gRPC codes — map each to the
 * nearest valid `HttpsError` code for the wire, while carrying the exact
 * code in `details.sttCode` so the client can reconstruct the precise
 * failure reason (`FirebaseAiRepository.transcribe` reads it) rather than
 * inferring from the coarser gRPC bucket.
 * @const {!Object<string, string>}
 */
const SPEECH_ERROR_TO_HTTPS_CODE = {
  "invalid-argument": "invalid-argument",
  "unsupported_audio_format": "invalid-argument",
  "audio_too_large": "invalid-argument",
  "transcription_failed": "internal",
  "provider_unavailable": "unavailable",
  "timeout": "deadline-exceeded",
};

/**
 * @param {!Error} err
 * @return {!HttpsError}
 */
const toSpeechHttpsError = (err) => {
  if (err instanceof SpeechError) {
    const grpcCode = SPEECH_ERROR_TO_HTTPS_CODE[err.code] || "internal";
    return new HttpsError(grpcCode, err.message, {sttCode: err.code});
  }
  console.error("aiTranscribe: unhandled error", err);
  return new HttpsError(
      "internal", "Couldn't transcribe that audio. Please try again.",
      {sttCode: "transcription_failed"});
};

/**
 * Speech-to-text for the chat composer's mic button: one audio clip in, one
 * transcript out — no Firestore write, no LLM call, no text-to-speech. The
 * client puts the returned text in the composer for the user to edit/send
 * via the existing `aiChat` path. All orchestration (validation, provider
 * selection, error translation) lives in `./ai/speech/gateway.js` so it is
 * unit-testable without the network; this handler only wires the real
 * OpenAI client and maps errors.
 */
exports.aiTranscribe = onCall(
    {
      // Gemini backs the default route and is required. OpenAI is the
      // OPTIONAL fallback — add OPENAI_API_KEY here (and set the secret) to
      // enable it; omitted so the function deploys Gemini-only by default.
      secrets: [GEMINI_API_KEY],
      region: "us-central1",
      // A single transcription call for a short voice note; generous
      // headroom over the platform default without inviting long-poll abuse.
      timeoutSeconds: 120,
    },
    async (request) => {
      const auth = request.auth;
      if (!auth) {
        throw new HttpsError("unauthenticated", "Sign in to use Ask.");
      }

      const data = request.data || {};
      const audioBase64 = (data.audioBase64 || "").toString();
      const mimeType = (data.mimeType || "").toString();
      const languageHint = typeof data.languageHint === "string" ?
        data.languageHint : undefined;

      const genai = new GoogleGenAI({apiKey: GEMINI_API_KEY.value()});
      // OpenAI fallback is wired only when its key is bound at runtime — i.e.
      // OPENAI_API_KEY was set AND listed in this function's `secrets` array
      // (Firebase populates `process.env` only for bound secrets). Otherwise
      // it's null and the router runs Gemini-only, skipping the OpenAI route.
      const openaiKey = process.env.OPENAI_API_KEY;
      const openai = openaiKey ? new OpenAI({apiKey: openaiKey}) : null;
      const registry = buildSpeechRegistry(genai, openai);
      const route = speechRouter.resolve("speech_to_text");

      try {
        return await transcribeAudio({
          provider: speechProviderForCapability(registry, "speech_to_text"),
          audioBase64,
          mimeType,
          languageHint,
          // Never carries raw audio or the transcript itself — only its
          // length would even be safe to add, and `./ai/speech/gateway.js`
          // doesn't include it.
          logEvent: (event) => logger.info("aiTranscribe", {
            capability: "speech_to_text",
            provider: route.provider,
            model: route.model,
            ...event,
          }),
        });
      } catch (err) {
        throw toSpeechHttpsError(err);
      }
    },
);

// --- weeklyCoachReport (proactive push, ADR-003's "coach speaks first") -----

/**
 * Every Monday morning (Cairo time), appends a deterministic weekly recap —
 * training done, diet adherence vs plan, spend — as an assistant message in
 * each user's most recent Ask conversation, so it's waiting there when they
 * next open the app. No model call per user: the text is a template over
 * real numbers (`./ai/coach_report.js`), which keeps this free to run and
 * impossible to hallucinate.
 *
 * Delivery targets come from Auth (every real account), but only users with
 * at least one conversation receive anything — someone who never used Ask
 * shouldn't find a fabricated conversation appearing. Per-user failures are
 * logged and skipped so one bad document can't abort the whole fan-out.
 */
exports.weeklyCoachReport = onSchedule(
    {
      // 08:00 Mondays, Cairo — the app's default-currency audience (EGP).
      schedule: "0 8 * * 1",
      timeZone: "Africa/Cairo",
      region: "us-central1",
      timeoutSeconds: 540,
    },
    async () => {
      const store = new FirestoreStore(db);
      let reported = 0;
      let skipped = 0;
      let pageToken;
      do {
        const list = await getAuth().listUsers(1000, pageToken);
        for (const user of list.users) {
          try {
            const delivered = await deliverWeeklyReport(
                {store, uid: user.uid, now: new Date()});
            if (delivered) reported++;
            else skipped++;
          } catch (err) {
            skipped++;
            logger.warn("weeklyCoachReport", {
              uid: user.uid,
              stage: "error",
              message: err && err.message,
            });
          }
        }
        pageToken = list.pageToken;
      } while (pageToken);
      logger.info("weeklyCoachReport", {reported, skipped});
    },
);
