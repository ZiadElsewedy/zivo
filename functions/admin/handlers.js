/**
 * ZIVO Admin — the deployed entry points: the admin-only callables and the
 * Firestore triggers that derive product events. Thin: every decision
 * is in `./events.js` (pure) and `./service.js`.
 *
 * Exported from `functions/index.js` via `buildAdminHandlers(...)`.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentWritten,
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {AdminError} = require("./service");
const {
  sessionEvents,
  appOpenEvents,
  aiEvents,
  workoutPlanEvents,
  dietPlanEvents,
  toMillis,
} = require("./events");

const REGION = "us-central1";

/**
 * @param {{service: !AdminService,
 *   eraseAccount: function(string): !Promise<void>,
 *   requireRecentAuth: function(!Object, string): void}} deps
 * @return {!Object<string, !Function>} The exports to deploy.
 */
function buildAdminHandlers({service, eraseAccount, requireRecentAuth}) {
  /**
   * An admin callable: checks the caller is an admin (server-side, every
   * call), runs [fn], and maps failures to HttpsErrors without leaking
   * internals.
   * @param {string} label
   * @param {function(!Object, string): !Promise<*>} fn
   * @return {!Function}
   */
  const adminCall = (label, fn) => onCall({region: REGION},
      async (request) => {
        try {
          const adminUid = await service.assertAdmin(request.auth);
          return await fn(request, adminUid);
        } catch (err) {
          if (err instanceof HttpsError) throw err;
          if (err instanceof AdminError) {
            throw new HttpsError(err.code, err.message);
          }
          logger.error(`${label}: failed`, {errorMessage: err.message});
          throw new HttpsError("internal", "That didn't work. Try again.");
        }
      });

  /**
   * Runs a trigger body, logging rather than throwing: an analytics miss
   * must never surface anywhere, and a retry storm is worse than a gap the
   * rebuild can close.
   * @param {string} label
   * @param {function(): !Promise<void>} body
   * @return {!Promise<void>}
   */
  const quietly = async (label, body) => {
    try {
      await body();
    } catch (err) {
      logger.warn(`${label}: skipped`, {errorMessage: err.message});
    }
  };

  /**
   * @param {string} uid
   * @param {!Array<{name: string, props: !Object}>} events
   * @param {string} sourceId
   * @param {(!Date|undefined)} at
   * @return {!Promise<void>}
   */
  const recordAll = async (uid, events, sourceId, at) => {
    for (const event of events) {
      await service.recordEvent(uid, event, {sourceId, at});
    }
  };

  const data = (snap) => (snap && snap.exists ? snap.data() : null);

  return {
    // --- callables ---------------------------------------------------------

    adminOverview: adminCall("adminOverview", (req) => service.overview({
      utcOffsetMinutes: Number.isFinite(req.data && req.data.utcOffsetMinutes) ?
        Math.trunc(req.data.utcOffsetMinutes) : undefined,
    })),

    adminListUsers: adminCall("adminListUsers",
        (req) => service.listUsers(req.data)),

    adminGetUser: adminCall("adminGetUser",
        (req) => service.userDetail(req.data && req.data.uid)),

    adminActivity: adminCall("adminActivity",
        (req) => service.activity(req.data)),

    adminSetUserDisabled: adminCall("adminSetUserDisabled",
        (req, adminUid) => service.setDisabled(adminUid, req.data)),

    adminDeleteUser: adminCall("adminDeleteUser", (req, adminUid) => {
      // Irreversible: like the user's own deletion, a token alone is not
      // enough — the admin must have re-proved their credential just now.
      requireRecentAuth(req.auth, "delete an account");
      return service.deleteUser(adminUid, req.data, eraseAccount);
    }),

    adminRebuildSummaries: adminCall("adminRebuildSummaries",
        (req) => service.rebuild(req.data)),

    // --- triggers ----------------------------------------------------------

    adminOnProfileWritten: onDocumentWritten(
        {document: "users/{uid}", region: REGION},
        (event) => quietly("adminOnProfileWritten", async () => {
          const before = data(event.data.before);
          const after = data(event.data.after);
          if (!after || (before && before.name === after.name)) return;
          await service.syncProfile(event.params.uid, after);
        })),

    adminOnDeviceSession: onDocumentWritten(
        {document: "users/{uid}/session/{docId}", region: REGION},
        (event) => quietly("adminOnDeviceSession", async () => {
          const after = data(event.data.after);
          const events = appOpenEvents(data(event.data.before), after);
          if (!events.length) return;
          const at = toMillis(after.lastSeenAt);
          await recordAll(event.params.uid, events, after.sessionId,
              at ? new Date(at) : undefined);
        })),

    adminOnWorkoutSession: onDocumentWritten(
        {document: "users/{uid}/workoutSessions/{sessionId}",
          region: REGION},
        (event) => quietly("adminOnWorkoutSession", async () => {
          const events = sessionEvents(
              data(event.data.before), data(event.data.after));
          // Each (session, event) pair is recorded once however often the
          // trigger fires — see eventId().
          await recordAll(event.params.uid, events, event.params.sessionId);
        })),

    adminOnWorkoutPlan: onDocumentCreated(
        {document: "users/{uid}/workoutPlans/{planId}", region: REGION},
        (event) => quietly("adminOnWorkoutPlan", () => recordAll(
            event.params.uid, workoutPlanEvents(data(event.data)),
            event.params.planId))),

    adminOnDietPlan: onDocumentCreated(
        {document: "users/{uid}/dietPlans/{planId}", region: REGION},
        (event) => quietly("adminOnDietPlan", () => recordAll(
            event.params.uid, dietPlanEvents(data(event.data)),
            event.params.planId))),

    adminOnAiUsage: onDocumentCreated(
        {document: "users/{uid}/aiUsage/{usageId}", region: REGION},
        (event) => quietly("adminOnAiUsage", async () => {
          const record = data(event.data);
          const at = record && toMillis(record.createdAt);
          await recordAll(event.params.uid, aiEvents(record),
              event.params.usageId, at ? new Date(at) : undefined);
        })),
  };
}

module.exports = {buildAdminHandlers};
