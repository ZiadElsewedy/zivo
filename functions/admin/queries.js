/**
 * ZIVO Admin — request validation and the shapes that leave the server.
 *
 * Pure: turns an untrusted admin request into a bounded query plan, and an
 * `adminUsers` document into the row an admin is allowed to see. The row
 * projection is the privacy boundary — a field that is not copied here does
 * not reach the Admin Console, whatever the summary document holds.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** "Active" = seen in the last 7 days. */
const ACTIVE_WINDOW_DAYS = 7;
/** "Inactive" = not seen in the last 30 days. */
const INACTIVE_AFTER_DAYS = 30;
/** "New" = created in the last 7 days. */
const NEW_WINDOW_DAYS = 7;

const MAX_PAGE_SIZE = 50;
const DEFAULT_PAGE_SIZE = 25;

/** The segments the users table can show. */
const SEGMENTS = ["all", "active", "inactive", "new"];

/**
 * The attribute filters, each a single equality on an indexed field (see
 * firestore.indexes.json — one composite index per field × sort).
 */
const FILTER_FIELDS = {
  status: (v) => ["active", "disabled"].includes(v) ? v : undefined,
  platform: (v) => shortString(v),
  appVersion: (v) => shortString(v),
  hasWorkoutPlan: (v) => typeof v === "boolean" ? v : undefined,
};

/**
 * A validated users-table query.
 * @param {*} data `request.data`
 * @param {number} nowMs
 * @return {{segment: string, filter: ?{field: string, value: *},
 *   search: ?string, pageSize: number, cursor: ?string,
 *   orderField: string, range: ?{field: string, op: string, value: !Date}}}
 */
function parseUserQuery(data, nowMs) {
  const d = data && typeof data === "object" ? data : {};
  const segment = SEGMENTS.includes(d.segment) ? d.segment : "all";
  let filter = null;
  if (d.filter && typeof d.filter === "object" &&
      Object.prototype.hasOwnProperty.call(FILTER_FIELDS, d.filter.field)) {
    const value = FILTER_FIELDS[d.filter.field](d.filter.value);
    if (value !== undefined) filter = {field: d.filter.field, value};
  }
  const search = typeof d.search === "string" ?
    d.search.trim().toLowerCase().slice(0, 120) || null : null;
  const size = Number.isInteger(d.pageSize) ? d.pageSize : DEFAULT_PAGE_SIZE;
  const pageSize = Math.min(Math.max(size, 1), MAX_PAGE_SIZE);
  const cursor = typeof d.cursor === "string" &&
    /^[A-Za-z0-9_-]{1,128}$/.test(d.cursor) ? d.cursor : null;

  let orderField = "lastActiveAt";
  let range = null;
  switch (segment) {
    case "active":
      range = {field: "lastActiveAt", op: ">=",
        value: new Date(nowMs - ACTIVE_WINDOW_DAYS * DAY_MS)};
      break;
    case "inactive":
      range = {field: "lastActiveAt", op: "<",
        value: new Date(nowMs - INACTIVE_AFTER_DAYS * DAY_MS)};
      break;
    case "new":
      orderField = "createdAt";
      range = {field: "createdAt", op: ">=",
        value: new Date(nowMs - NEW_WINDOW_DAYS * DAY_MS)};
      break;
    default:
      break;
  }
  return {segment, filter, search, pageSize, cursor, orderField, range};
}

/**
 * The users-table row for one summary document. Everything an admin sees
 * about a user in a list comes through here.
 * @param {string} uid
 * @param {!Object} s The `adminUsers/{uid}` data.
 * @return {!Object}
 */
function toUserRow(uid, s) {
  return {
    uid,
    displayName: shortString(s.displayName, 120) || null,
    emailMasked: shortString(s.emailMasked, 200) || null,
    createdAt: iso(s.createdAt),
    lastActiveAt: iso(s.lastActiveAt),
    status: s.status === "disabled" ? "disabled" : "active",
    platform: shortString(s.platform) || null,
    appVersion: shortString(s.appVersion) || null,
    hasWorkoutPlan: s.hasWorkoutPlan === true,
    workoutsCompleted: count(s.workoutsCompleted),
    aiRequests: count(s.aiRequests),
    aiTokens: count(s.aiTokensIn) + count(s.aiTokensOut),
    lastEvent: s.lastEvent && typeof s.lastEvent.name === "string" ?
      {name: s.lastEvent.name, at: iso(s.lastEvent.at)} : null,
  };
}

/**
 * The detail view: the row plus the workout and usage breakdowns. Still
 * counts and dates only.
 * @param {string} uid
 * @param {!Object} s
 * @return {!Object}
 */
function toUserDetail(uid, s) {
  const usage = s.usage && typeof s.usage === "object" ? s.usage : {};
  const features = {};
  for (const [k, v] of Object.entries(usage)) {
    if (/^[a-z0-9_]{1,64}$/.test(k)) features[k] = count(v);
  }
  return Object.assign(toUserRow(uid, s), {
    workoutPlans: count(s.workoutPlans),
    workoutPlanCreatedAt: iso(s.workoutPlanCreatedAt),
    workoutsStarted: count(s.workoutsStarted),
    workoutsAbandoned: count(s.workoutsAbandoned),
    lastWorkoutAt: iso(s.lastWorkoutAt),
    aiTokensIn: count(s.aiTokensIn),
    aiTokensOut: count(s.aiTokensOut),
    aiCostUsd: Number.isFinite(s.aiCostUsd) ? s.aiCostUsd : 0,
    features,
  });
}

/**
 * An event as the console sees it: name, time, and whitelisted properties.
 * @param {string} id
 * @param {!Object} e
 * @return {!Object}
 */
function toEvent(id, e) {
  const props = {};
  const p = e.props && typeof e.props === "object" ? e.props : {};
  for (const [k, v] of Object.entries(p)) {
    if (typeof v === "number" && Number.isFinite(v)) props[k] = v;
    else if (typeof v === "boolean") props[k] = v;
    else if (typeof v === "string" && v.length <= 64) props[k] = v;
  }
  return {id, uid: e.uid, name: e.name, at: iso(e.at), props};
}

/**
 * The start of the caller's local day, `days` days back.
 * @param {number} nowMs
 * @param {number} offsetMinutes
 * @param {number} daysBack 0 = today.
 * @return {!Date}
 */
function localDayStart(nowMs, offsetMinutes, daysBack = 0) {
  const off = Number.isFinite(offsetMinutes) &&
    Math.abs(offsetMinutes) <= 14 * 60 ? offsetMinutes : 0;
  const local = nowMs + off * 60000;
  const startLocal = local - (((local % DAY_MS) + DAY_MS) % DAY_MS);
  return new Date(startLocal - off * 60000 - daysBack * DAY_MS);
}

/**
 * @param {*} v
 * @param {number=} max
 * @return {(string|undefined)}
 */
function shortString(v, max = 40) {
  return typeof v === "string" && v.length > 0 && v.length <= max ?
    v : undefined;
}

/**
 * @param {*} v
 * @return {number}
 */
function count(v) {
  return Number.isFinite(v) && v > 0 ? Math.round(v) : 0;
}

/**
 * @param {*} v A Timestamp or Date.
 * @return {?string}
 */
function iso(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  return null;
}

module.exports = {
  DAY_MS,
  ACTIVE_WINDOW_DAYS,
  INACTIVE_AFTER_DAYS,
  NEW_WINDOW_DAYS,
  MAX_PAGE_SIZE,
  parseUserQuery,
  toUserRow,
  toUserDetail,
  toEvent,
  localDayStart,
};
