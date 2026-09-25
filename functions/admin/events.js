/**
 * ZIVO Admin — the product-event vocabulary and the pure rules that turn a
 * Firestore write into an event and an event into a change to the per-user
 * admin summary. See docs/ADMIN.md and ADR-018.
 *
 * WHY EVENTS ARE DERIVED ON THE SERVER. Every meaningful thing a user does
 * already lands in a document ZIVO owns — a workout session changes status,
 * a plan is created, the AI gateway writes an `aiUsage` record, a launch
 * claims `session/current`. Firestore triggers watch those writes and emit
 * the event, so:
 *   - the client has no analytics code and no new write channel to abuse;
 *   - an event can't be forged — it exists because the real record does;
 *   - nothing here reads content: a session contributes its STATUS, never
 *     its exercises; an AI request contributes its token count, never its
 *     conversation.
 *
 * Everything in this file is pure (no Firestore, no clock) so it is pinned
 * by `events.test.js`. `./store.js` applies what it decides.
 */

/**
 * The only event names that exist. Deliberately short — product milestones,
 * not interactions.
 * @enum {string}
 */
const AdminEvent = {
  ACCOUNT_CREATED: "account_created",
  APP_OPENED: "app_opened",
  WORKOUT_PLAN_CREATED: "workout_plan_created",
  WORKOUT_STARTED: "workout_started",
  WORKOUT_COMPLETED: "workout_completed",
  WORKOUT_ABANDONED: "workout_abandoned",
  WORKOUT_VOIDED: "workout_voided",
  AI_REQUEST: "ai_request",
  DIET_PLAN_CREATED: "diet_plan_created",
  DIET_IMPORTED: "diet_imported",
  ACCOUNT_DISABLED: "account_disabled",
  ACCOUNT_ENABLED: "account_enabled",
  ACCOUNT_DELETED: "account_deleted",
};

/**
 * Events an ADMIN causes. They are recorded, but they are not the user
 * being active, so they never move `lastActiveAt`.
 */
const ADMIN_ACTIONS = new Set([
  AdminEvent.ACCOUNT_DISABLED,
  AdminEvent.ACCOUNT_ENABLED,
  AdminEvent.ACCOUNT_DELETED,
]);

/** How long an event is kept (Firestore TTL on `expireAt`). */
const EVENT_RETENTION_DAYS = 180;

/**
 * A workout session write → the events it means. Only STATUS transitions
 * count; the dozens of set-by-set updates a live session makes produce
 * nothing.
 * @param {?Object} before The session doc before the write (null on create).
 * @param {?Object} after The session doc after the write (null on delete).
 * @return {!Array<{name: string, props: !Object}>}
 */
function sessionEvents(before, after) {
  // A delete is account erasure or discarding an empty session — neither
  // is product activity.
  if (!after) return [];
  const was = before ? before.status : null;
  const now = after.status;
  if (was === now) return [];
  const events = [];
  if (!before) {
    events.push({name: AdminEvent.WORKOUT_STARTED, props: {}});
  }
  if (now === "completed") {
    events.push({
      name: AdminEvent.WORKOUT_COMPLETED,
      props: durationProps(after),
    });
  } else if (now === "abandoned") {
    events.push({name: AdminEvent.WORKOUT_ABANDONED, props: {}});
  } else if (now === "voided") {
    // A withdrawn session must stop counting as completed, or the admin
    // number drifts above the user's own history.
    events.push({
      name: AdminEvent.WORKOUT_VOIDED,
      props: {wasCompleted: was === "completed"},
    });
  }
  return events;
}

/**
 * The session's length in whole minutes, when it can be told.
 * @param {!Object} session
 * @return {!Object}
 */
function durationProps(session) {
  if (Number.isInteger(session.correctedDurationMinutes)) {
    return {durationMinutes: session.correctedDurationMinutes};
  }
  const start = toMillis(session.startedAt);
  const end = toMillis(session.completedAt);
  if (start == null || end == null || end < start) return {};
  const paused = Number.isFinite(session.pausedAccumMs) ?
    session.pausedAccumMs : 0;
  const minutes = Math.round((end - start - paused) / 60000);
  return minutes >= 0 && minutes <= 1440 ? {durationMinutes: minutes} : {};
}

/**
 * A `session/current` write → `app_opened` when a NEW session was claimed
 * (the client claims once per launch — see DeviceSessionGuard).
 * @param {?Object} before
 * @param {?Object} after
 * @return {!Array<{name: string, props: !Object}>}
 */
function appOpenEvents(before, after) {
  if (!after || typeof after.sessionId !== "string") return [];
  if (before && before.sessionId === after.sessionId) return [];
  return [{
    name: AdminEvent.APP_OPENED,
    props: pickStrings(after, ["platform", "appVersion"]),
  }];
}

/**
 * A new `aiUsage` record → `ai_request`. Only counts — the record holds no
 * content, and nothing but these fields is copied.
 * @param {!Object} record
 * @return {!Array<{name: string, props: !Object}>}
 */
function aiEvents(record) {
  if (!record) return [];
  const props = pickStrings(record, ["feature", "provider", "status"]);
  props.tokensIn = finite(record.tokensIn);
  props.tokensOut = finite(record.tokensOut);
  props.costUsd = finite(record.costUsd);
  return [{name: AdminEvent.AI_REQUEST, props}];
}

/**
 * A created workout plan → `workout_plan_created` with how it was made.
 * @param {!Object} plan
 * @return {!Array<{name: string, props: !Object}>}
 */
function workoutPlanEvents(plan) {
  if (!plan) return [];
  return [{
    name: AdminEvent.WORKOUT_PLAN_CREATED,
    props: pickStrings(plan, ["source"]),
  }];
}

/**
 * A created diet plan → `diet_imported` when it came from a document, a
 * photo, dictation or ZIVO's generator; `diet_plan_created` when written by
 * hand.
 * @param {!Object} plan
 * @return {!Array<{name: string, props: !Object}>}
 */
function dietPlanEvents(plan) {
  if (!plan) return [];
  const source = typeof plan.source === "string" ? plan.source : "manual";
  return [{
    name: source === "manual" ?
      AdminEvent.DIET_PLAN_CREATED : AdminEvent.DIET_IMPORTED,
    props: {source},
  }];
}

/**
 * How one event changes the user's admin summary: plain field values to
 * `set`, counters to `increment`, and whether it counts as activity.
 * @param {{name: string, props: !Object}} event
 * @param {!Date} at When it happened.
 * @return {{set: !Object, inc: !Object}}
 */
function summaryPatch(event, at) {
  const set = {};
  const inc = {};
  const p = event.props || {};
  if (!ADMIN_ACTIONS.has(event.name)) {
    set.lastActiveAt = at;
    set.lastEvent = {name: event.name, at};
  }
  switch (event.name) {
    case AdminEvent.APP_OPENED:
      inc["usage.app_opened"] = 1;
      if (p.platform) set.platform = p.platform;
      if (p.appVersion) set.appVersion = p.appVersion;
      break;
    case AdminEvent.WORKOUT_PLAN_CREATED:
      inc.workoutPlans = 1;
      set.hasWorkoutPlan = true;
      break;
    case AdminEvent.WORKOUT_STARTED:
      inc.workoutsStarted = 1;
      break;
    case AdminEvent.WORKOUT_COMPLETED:
      inc.workoutsCompleted = 1;
      set.lastWorkoutAt = at;
      break;
    case AdminEvent.WORKOUT_ABANDONED:
      inc.workoutsAbandoned = 1;
      break;
    case AdminEvent.WORKOUT_VOIDED:
      if (p.wasCompleted) inc.workoutsCompleted = -1;
      // Withdrawing a record is housekeeping, not a visit.
      delete set.lastActiveAt;
      delete set.lastEvent;
      break;
    case AdminEvent.AI_REQUEST:
      inc.aiRequests = 1;
      inc.aiTokensIn = p.tokensIn || 0;
      inc.aiTokensOut = p.tokensOut || 0;
      inc.aiCostUsd = p.costUsd || 0;
      if (p.feature) inc[`usage.ai_${safeKey(p.feature)}`] = 1;
      break;
    case AdminEvent.DIET_IMPORTED:
      inc["usage.diet_imported"] = 1;
      break;
    case AdminEvent.DIET_PLAN_CREATED:
      inc["usage.diet_plan_created"] = 1;
      break;
    case AdminEvent.ACCOUNT_DISABLED:
      set.status = "disabled";
      break;
    case AdminEvent.ACCOUNT_ENABLED:
      set.status = "active";
      break;
    default:
      break;
  }
  return {set, inc};
}

/**
 * The deterministic id of the event a source document produced, so a
 * trigger delivered twice (Cloud Functions are at-least-once) records it
 * once.
 * @param {string} name
 * @param {string} uid
 * @param {string} sourceId
 * @return {string}
 */
function eventId(name, uid, sourceId) {
  return `${name}_${safeKey(uid)}_${safeKey(sourceId)}`.slice(0, 700);
}

/**
 * The address shown to an admin: enough to recognise an account, not
 * enough to harvest it. `ziad@gmail.com` → `zi**@gmail.com`.
 * @param {*} email
 * @return {?string}
 */
function maskEmail(email) {
  if (typeof email !== "string" || !email.includes("@")) return null;
  const [local, domain] = email.split("@");
  const keep = local.length <= 2 ? 1 : 2;
  return `${local.slice(0, keep)}${"*".repeat(
      Math.max(local.length - keep, 1))}@${domain}`;
}

/**
 * The lower-cased search key for a name/email prefix search.
 * @param {*} value
 * @return {?string}
 */
function searchKey(value) {
  if (typeof value !== "string") return null;
  const key = value.trim().toLowerCase();
  return key.length ? key.slice(0, 120) : null;
}

/**
 * @param {!Object} source
 * @param {!Array<string>} keys
 * @return {!Object} Only the listed keys, only when they are short strings.
 */
function pickStrings(source, keys) {
  const out = {};
  for (const k of keys) {
    const v = source[k];
    if (typeof v === "string" && v.length > 0 && v.length <= 64) out[k] = v;
  }
  return out;
}

/**
 * @param {*} n
 * @return {number} A finite, non-negative number, else 0.
 */
function finite(n) {
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/**
 * @param {string} s
 * @return {string} Safe as a document id segment or a field-path segment.
 */
function safeKey(s) {
  return String(s).replace(/[^A-Za-z0-9_-]/g, "_");
}

/**
 * @param {*} v A Firestore Timestamp, a Date, or millis.
 * @return {?number}
 */
function toMillis(v) {
  if (v == null) return null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Number.isFinite(v) ? v : null;
}

module.exports = {
  AdminEvent,
  ADMIN_ACTIONS,
  EVENT_RETENTION_DAYS,
  sessionEvents,
  appOpenEvents,
  aiEvents,
  workoutPlanEvents,
  dietPlanEvents,
  summaryPatch,
  eventId,
  maskEmail,
  searchKey,
  toMillis,
};
