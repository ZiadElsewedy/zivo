/**
 * ZIVO Admin — the Firestore/Auth side of the Admin Console.
 *
 * Three collections, all Admin-SDK-only (every client is denied by
 * `firestore.rules`, admins included — the console reads through the
 * callables in `functions/index.js`, never Firestore directly):
 *
 *   adminUsers/{uid}   one summary per account: dates, platform, status and
 *                      COUNTERS. Maintained incrementally by the triggers.
 *   adminEvents/{id}   the product-event log (`./events.js` vocabulary),
 *                      `{uid, name, at, props, expireAt}`; TTL on expireAt.
 *   adminAudit/{id}    who (admin) did what (disable/enable/delete) to whom.
 *
 * Every metric is a server-side count()/sum() aggregation over those — no
 * handler ever downloads a user's documents to add them up. The only reads
 * of a user's own subcollections happen in `rebuildUser`, which counts them
 * (aggregations again) and reads nothing's content.
 */

const {
  AdminEvent,
  EVENT_RETENTION_DAYS,
  summaryPatch,
  eventId,
  maskEmail,
  searchKey,
  toMillis,
} = require("./events");
const {
  DAY_MS,
  ACTIVE_WINDOW_DAYS,
  parseUserQuery,
  toUserRow,
  toUserDetail,
  toEvent,
  localDayStart,
} = require("./queries");

const USERS = "adminUsers";
const EVENTS = "adminEvents";
const AUDIT = "adminAudit";

/** Event names the activity page breaks down. */
const ACTIVITY_NAMES = [
  AdminEvent.APP_OPENED,
  AdminEvent.WORKOUT_PLAN_CREATED,
  AdminEvent.WORKOUT_STARTED,
  AdminEvent.WORKOUT_COMPLETED,
  AdminEvent.WORKOUT_ABANDONED,
  AdminEvent.AI_REQUEST,
  AdminEvent.DIET_IMPORTED,
  AdminEvent.ACCOUNT_CREATED,
  AdminEvent.ACCOUNT_DELETED,
];

/** The AI `feature` values the rebuild counts (see ai/shared/usage_log.js). */
const AI_FEATURES = [
  "chat", "workout_import", "diet_import", "diet_generate", "food_search",
  "transcribe",
];

/** A failure the callable maps to an HttpsError with this code. */
class AdminError extends Error {
  /**
   * @param {string} code An HttpsError code.
   * @param {string} message Safe to show.
   */
  constructor(code, message) {
    super(message);
    this.name = "AdminError";
    this.code = code;
  }
}

/** The admin data service. */
class AdminService {
  /**
   * @param {{db: !Object, auth: !Object, FieldValue: !Object,
   *   AggregateField: !Object, now: (undefined|function(): number)}} deps
   */
  constructor({db, auth, FieldValue, AggregateField, now}) {
    this.db = db;
    this.auth = auth;
    this.FieldValue = FieldValue;
    this.AggregateField = AggregateField;
    this.now = now || (() => Date.now());
  }

  // --- authorization -------------------------------------------------------

  /**
   * The server half of "is this caller an admin". The token claim is the
   * fast check; the Auth record is re-read so a revoked admin or a disabled
   * account loses access immediately rather than when its token expires.
   * @param {?Object} auth `request.auth`
   * @return {!Promise<string>} The admin's uid.
   */
  async assertAdmin(auth) {
    if (!auth) throw new AdminError("unauthenticated", "Sign in first.");
    if (!auth.token || auth.token.admin !== true) {
      throw new AdminError("permission-denied", "Admins only.");
    }
    let record;
    try {
      record = await this.auth.getUser(auth.uid);
    } catch (_err) {
      throw new AdminError("permission-denied", "Admins only.");
    }
    const claims = record.customClaims || {};
    if (claims.admin !== true || record.disabled) {
      throw new AdminError("permission-denied", "Admins only.");
    }
    return auth.uid;
  }

  // --- event recording (triggers) -----------------------------------------

  /**
   * Records [event] for [uid] and folds it into their summary — once, even
   * when the trigger that produced it is delivered twice.
   * @param {string} uid
   * @param {{name: string, props: !Object}} event
   * @param {{sourceId: (string|undefined), at: (!Date|undefined)}} opts
   * @return {!Promise<boolean>} Whether anything was written.
   */
  async recordEvent(uid, event, {sourceId, at} = {}) {
    const when = at || new Date(this.now());
    if (!(await this.ensureSummary(uid))) return false;
    const events = this.db.collection(EVENTS);
    const eventRef = sourceId ?
      events.doc(eventId(event.name, uid, sourceId)) : events.doc();
    const summaryRef = this.db.collection(USERS).doc(uid);
    return this.db.runTransaction(async (tx) => {
      const [existing, summary] = await Promise.all([
        sourceId ? tx.get(eventRef) : Promise.resolve(null),
        tx.get(summaryRef),
      ]);
      if (existing && existing.exists) return false;
      if (!summary.exists) return false; // erased meanwhile
      tx.create(eventRef, this._eventDoc(uid, event, when));
      tx.update(summaryRef, this._patchFields(summary.data(), event, when));
      return true;
    });
  }

  /**
   * Creates the account's summary from its Auth record if it has none, and
   * records `account_created` (at the Auth creation time) when it does.
   * False when the account no longer exists — a late trigger must never
   * resurrect a deleted user's summary.
   *
   * This is where `account_created` comes from: the first sign-in claims
   * `users/{uid}/session/current`, whose trigger lands here. (A 1st-gen Auth
   * `onCreate` trigger can't run on the codebase's Node 24 runtime.)
   * @param {string} uid
   * @return {!Promise<boolean>}
   */
  async ensureSummary(uid) {
    const ref = this.db.collection(USERS).doc(uid);
    if ((await ref.get()).exists) return true;
    const record = await this._authRecord(uid);
    if (!record) return false;
    const profile = await this.db.collection("users").doc(uid).get();
    const seed = this._seed(uid, record, profile.data() || {});
    try {
      await ref.create(seed);
    } catch (err) {
      if (err.code !== 6 && err.code !== "already-exists") throw err;
      return true; // a concurrent trigger seeded it and records the event
    }
    // Keyed by uid, so it is recorded once however many triggers race here.
    await this.recordEvent(uid, {name: AdminEvent.ACCOUNT_CREATED, props: {}},
        {sourceId: uid, at: seed.createdAt});
    return true;
  }

  /**
   * Keeps the summary's display name in step with the user's profile.
   * @param {string} uid
   * @param {?Object} profile
   * @return {!Promise<void>}
   */
  async syncProfile(uid, profile) {
    if (!profile || !(await this.ensureSummary(uid))) return;
    const name = typeof profile.name === "string" ?
      profile.name.slice(0, 120) : null;
    await this.db.collection(USERS).doc(uid).update({
      displayName: name,
      nameLower: searchKey(name),
    }).catch(() => undefined);
  }

  // --- reads (callables) ---------------------------------------------------

  /**
   * The dashboard's numbers, all aggregated server-side.
   * @param {{utcOffsetMinutes: (number|undefined)}} opts
   * @return {!Promise<!Object>}
   */
  async overview({utcOffsetMinutes} = {}) {
    const now = this.now();
    const today = localDayStart(now, utcOffsetMinutes, 0);
    const ago = (days) => new Date(now - days * DAY_MS);
    const users = this.db.collection(USERS);
    const events = this.db.collection(EVENTS);
    const named = (name) => events.where("name", "==", name);
    const sum = (f) => this.AggregateField.sum(f);

    const [
      totalUsers, newToday, newWeek, activeToday, active7, active30,
      withPlan, disabled, workoutsToday, aiToday, ai30, aiAll, series,
    ] = await Promise.all([
      count(users),
      count(users.where("createdAt", ">=", today)),
      count(users.where("createdAt", ">=", ago(7))),
      count(users.where("lastActiveAt", ">=", today)),
      count(users.where("lastActiveAt", ">=", ago(ACTIVE_WINDOW_DAYS))),
      count(users.where("lastActiveAt", ">=", ago(30))),
      count(users.where("hasWorkoutPlan", "==", true)),
      count(users.where("status", "==", "disabled")),
      count(named(AdminEvent.WORKOUT_COMPLETED).where("at", ">=", today)),
      count(named(AdminEvent.AI_REQUEST).where("at", ">=", today)),
      aggregate(named(AdminEvent.AI_REQUEST).where("at", ">=", ago(30)), {
        requests: this.AggregateField.count(),
        tokensIn: sum("props.tokensIn"),
        tokensOut: sum("props.tokensOut"),
        costUsd: sum("props.costUsd"),
      }),
      aggregate(users, {
        requests: sum("aiRequests"),
        tokensIn: sum("aiTokensIn"),
        tokensOut: sum("aiTokensOut"),
        costUsd: sum("aiCostUsd"),
      }),
      this._dailySeries(utcOffsetMinutes, 14, [
        AdminEvent.WORKOUT_COMPLETED,
        AdminEvent.APP_OPENED,
      ]),
    ]);

    return {
      generatedAt: new Date(now).toISOString(),
      users: {
        total: totalUsers, newToday, newThisWeek: newWeek,
        activeToday, active7d: active7, active30d: active30,
        withWorkoutPlan: withPlan, disabled,
      },
      workouts: {completedToday: workoutsToday},
      ai: {
        requestsToday: aiToday,
        last30d: numbers(ai30),
        allTime: numbers(aiAll),
      },
      series,
    };
  }

  /**
   * One page of the users table.
   * @param {*} data `request.data`
   * @return {!Promise<{users: !Array<!Object>, nextCursor: ?string}>}
   */
  async listUsers(data) {
    const q = parseUserQuery(data, this.now());
    const users = this.db.collection(USERS);

    if (q.search) return this._searchUsers(q);

    let query = users;
    if (q.filter) query = query.where(q.filter.field, "==", q.filter.value);
    if (q.range) query = query.where(q.range.field, q.range.op, q.range.value);
    query = query.orderBy(q.orderField, "desc");
    if (q.cursor) {
      const after = await users.doc(q.cursor).get();
      if (after.exists) query = query.startAfter(after);
    }
    const snap = await query.limit(q.pageSize + 1).get();
    const docs = snap.docs.slice(0, q.pageSize);
    return {
      users: docs.map((d) => toUserRow(d.id, d.data())),
      nextCursor: snap.docs.length > q.pageSize ?
        docs[docs.length - 1].id : null,
    };
  }

  /**
   * Prefix search on name and email, or an exact uid.
   * @param {!Object} q A parsed query with `search`.
   * @return {!Promise<{users: !Array<!Object>, nextCursor: ?string}>}
   */
  async _searchUsers(q) {
    const users = this.db.collection(USERS);
    const prefix = (field) => users
        .where(field, ">=", q.search)
        .where(field, "<", q.search + "")
        .orderBy(field)
        .limit(q.pageSize)
        .get();
    const [byName, byEmail, byUid] = await Promise.all([
      prefix("nameLower"),
      prefix("emailLower"),
      /^[A-Za-z0-9_-]{1,128}$/.test(q.search) ?
        users.doc(q.search).get() : Promise.resolve(null),
    ]);
    const seen = new Map();
    if (byUid && byUid.exists) seen.set(byUid.id, byUid.data());
    for (const d of [...byName.docs, ...byEmail.docs]) {
      if (!seen.has(d.id)) seen.set(d.id, d.data());
    }
    return {
      users: [...seen.entries()].slice(0, q.pageSize)
          .map(([id, s]) => toUserRow(id, s)),
      nextCursor: null,
    };
  }

  /**
   * One user's overview: the summary, what Auth says about the account, and
   * their recent events. No content from their own collections.
   * @param {*} uid
   * @return {!Promise<!Object>}
   */
  async userDetail(uid) {
    const id = requireUid(uid);
    await this.ensureSummary(id);
    const [snap, record, recent] = await Promise.all([
      this.db.collection(USERS).doc(id).get(),
      this._authRecord(id),
      this.db.collection(EVENTS).where("uid", "==", id)
          .orderBy("at", "desc").limit(25).get(),
    ]);
    if (!snap.exists || !record) {
      throw new AdminError("not-found", "That account doesn't exist.");
    }
    const detail = toUserDetail(id, snap.data());
    // Auth is canonical for the account's state; the summary can lag it.
    detail.status = record.disabled ? "disabled" : "active";
    detail.isAdmin = (record.customClaims || {}).admin === true;
    detail.providers = (record.providerData || [])
        .map((p) => p.providerId).filter((p) => typeof p === "string");
    detail.lastSignInAt = isoOf(record.metadata.lastSignInTime);
    detail.recentEvents = recent.docs.map((d) => toEvent(d.id, d.data()));
    return detail;
  }

  /**
   * The activity page: how often each meaningful event happened over the
   * window, plus the most recent events (paginated).
   * @param {*} data
   * @return {!Promise<!Object>}
   */
  async activity(data) {
    const d = data && typeof data === "object" ? data : {};
    const days = [1, 7, 30].includes(d.days) ? d.days : 7;
    const name = ACTIVITY_NAMES.includes(d.name) ? d.name : null;
    const since = new Date(this.now() - days * DAY_MS);
    const events = this.db.collection(EVENTS);

    let feed = events;
    if (name) feed = feed.where("name", "==", name);
    feed = feed.orderBy("at", "desc");
    if (typeof d.cursor === "string" && /^[A-Za-z0-9_-]{1,700}$/.test(
        d.cursor)) {
      const after = await events.doc(d.cursor).get();
      if (after.exists) feed = feed.startAfter(after);
    }

    const [counts, page] = await Promise.all([
      Promise.all(ACTIVITY_NAMES.map((n) => count(
          events.where("name", "==", n).where("at", ">=", since)))),
      feed.limit(51).get(),
    ]);
    const docs = page.docs.slice(0, 50);
    const names = await this._displayNames(docs.map((x) => x.data().uid));
    return {
      days,
      totals: Object.fromEntries(ACTIVITY_NAMES.map((n, i) => [n, counts[i]])),
      events: docs.map((x) => Object.assign(toEvent(x.id, x.data()), {
        displayName: names.get(x.data().uid) || null,
      })),
      nextCursor: page.docs.length > 50 ? docs[docs.length - 1].id : null,
    };
  }

  // --- account management --------------------------------------------------

  /**
   * Disables (suspends) or re-enables an account. Disabling also revokes
   * the account's refresh tokens so every device is signed out as soon as
   * its current ID token lapses.
   * @param {string} adminUid
   * @param {*} data `{uid, disabled}`
   * @return {!Promise<{status: string}>}
   */
  async setDisabled(adminUid, data) {
    const d = data && typeof data === "object" ? data : {};
    const uid = requireUid(d.uid);
    if (typeof d.disabled !== "boolean") {
      throw new AdminError("invalid-argument", "Say whether to disable.");
    }
    await this._assertManageable(adminUid, uid);
    await this.auth.updateUser(uid, {disabled: d.disabled});
    if (d.disabled) await this.auth.revokeRefreshTokens(uid);
    const name = d.disabled ?
      AdminEvent.ACCOUNT_DISABLED : AdminEvent.ACCOUNT_ENABLED;
    await this.recordEvent(uid, {name, props: {}});
    await this._audit(adminUid, name, uid);
    return {status: d.disabled ? "disabled" : "active"};
  }

  /**
   * Permanently deletes an account through the SAME erasure the user's own
   * "Delete account" runs ([eraseAccount]), after the checks.
   * @param {string} adminUid
   * @param {*} data `{uid, confirmUid}` — confirmUid must repeat uid.
   * @param {function(string): !Promise<void>} eraseAccount
   * @return {!Promise<{status: string}>}
   */
  async deleteUser(adminUid, data, eraseAccount) {
    const d = data && typeof data === "object" ? data : {};
    const uid = requireUid(d.uid);
    if (d.confirmUid !== uid) {
      throw new AdminError(
          "failed-precondition", "Confirm the account you are deleting.");
    }
    await this._assertManageable(adminUid, uid);
    await eraseAccount(uid);
    await this._audit(adminUid, AdminEvent.ACCOUNT_DELETED, uid);
    return {status: "deleted"};
  }

  /**
   * The admin-side cleanup after an account is erased (by the user or by
   * an admin): the summary goes (it names the person), the event history
   * stays pseudonymous and ages out with the TTL, and the deletion itself
   * is recorded.
   * @param {string} uid
   * @return {!Promise<void>}
   */
  async forgetUser(uid) {
    await this.db.collection(USERS).doc(uid).delete();
    await this.db.collection(EVENTS).add(this._eventDoc(
        uid, {name: AdminEvent.ACCOUNT_DELETED, props: {}},
        new Date(this.now())));
  }

  /**
   * Rebuilds summaries from source data, one Auth page at a time — for
   * accounts that existed before the triggers did, or after a trigger
   * outage. Counts only; the event history is not back-filled.
   * @param {*} data `{pageToken}`
   * @return {!Promise<{processed: number, nextPageToken: ?string}>}
   */
  async rebuild(data) {
    const token = data && typeof data.pageToken === "string" ?
      data.pageToken : undefined;
    const page = await this.auth.listUsers(50, token);
    for (const record of page.users) {
      await this.rebuildUser(record);
    }
    return {
      processed: page.users.length,
      nextPageToken: page.pageToken || null,
    };
  }

  /**
   * One account's summary, recomputed from its own collections with
   * count()/sum() aggregations and two single-document reads.
   * @param {!Object} record An Auth UserRecord.
   * @return {!Promise<void>}
   */
  async rebuildUser(record) {
    const uid = record.uid;
    const user = this.db.collection("users").doc(uid);
    const sum = (f) => this.AggregateField.sum(f);
    const sessions = user.collection("workoutSessions");
    const plans = user.collection("workoutPlans");
    const ai = user.collection("aiUsage");
    const [
      profile, device, planCount, firstPlan, started, completed, abandoned,
      lastWorkout, aiTotals, dietImports, ...featureCounts
    ] = await Promise.all([
      user.get(),
      user.collection("session").doc("current").get(),
      count(plans),
      plans.orderBy("createdAt").limit(1).get(),
      count(sessions),
      count(sessions.where("status", "==", "completed")),
      count(sessions.where("status", "==", "abandoned")),
      sessions.orderBy("completedAt", "desc").limit(1).get(),
      aggregate(ai, {
        requests: this.AggregateField.count(),
        tokensIn: sum("tokensIn"),
        tokensOut: sum("tokensOut"),
        costUsd: sum("costUsd"),
      }),
      count(user.collection("dietPlans").where(
          "source", "in", ["pdf", "photo", "dictated", "generated"])),
      ...AI_FEATURES.map((f) => count(ai.where("feature", "==", f))),
    ]);

    const seed = this._seed(uid, record, profile.data() || {});
    const dev = device.data() || {};
    const lastSeen = toMillis(dev.lastSeenAt);
    const refreshed = Date.parse(record.metadata.lastRefreshTime || "") ||
      Date.parse(record.metadata.lastSignInTime || "") || null;
    const lastActive = Math.max(
        lastSeen || 0, refreshed || 0, seed.createdAt.getTime());
    const lastWorkoutDoc = lastWorkout.docs[0];
    const usage = {diet_imported: dietImports};
    AI_FEATURES.forEach((f, i) => {
      usage[`ai_${f}`] = featureCounts[i];
    });

    await this.db.collection(USERS).doc(uid).set(Object.assign(seed, {
      lastActiveAt: new Date(lastActive),
      platform: typeof dev.platform === "string" ? dev.platform : null,
      appVersion: typeof dev.appVersion === "string" ?
        dev.appVersion : null,
      workoutPlans: planCount,
      hasWorkoutPlan: planCount > 0,
      workoutPlanCreatedAt: firstPlan.docs[0] ?
        firstPlan.docs[0].get("createdAt") || null : null,
      workoutsStarted: started,
      workoutsCompleted: completed,
      workoutsAbandoned: abandoned,
      lastWorkoutAt: lastWorkoutDoc ?
        lastWorkoutDoc.get("completedAt") || null : null,
      aiRequests: aiTotals.requests || 0,
      aiTokensIn: aiTotals.tokensIn || 0,
      aiTokensOut: aiTotals.tokensOut || 0,
      aiCostUsd: aiTotals.costUsd || 0,
      usage,
      rebuiltAt: new Date(this.now()),
    }), {merge: true});
  }

  // --- internals -----------------------------------------------------------

  /**
   * @param {string} adminUid
   * @param {string} uid
   * @return {!Promise<void>}
   */
  async _assertManageable(adminUid, uid) {
    if (uid === adminUid) {
      throw new AdminError(
          "failed-precondition", "You can't do this to your own account.");
    }
    const record = await this._authRecord(uid);
    if (!record) {
      throw new AdminError("not-found", "That account doesn't exist.");
    }
    if ((record.customClaims || {}).admin === true) {
      throw new AdminError(
          "failed-precondition", "Admin accounts can't be managed here.");
    }
  }

  /**
   * @param {string} actorUid
   * @param {string} action
   * @param {string} targetUid
   * @return {!Promise<void>}
   */
  async _audit(actorUid, action, targetUid) {
    await this.db.collection(AUDIT).add({
      actorUid, action, targetUid, at: new Date(this.now()),
    });
  }

  /**
   * @param {string} uid
   * @return {!Promise<?Object>} The Auth record, or null when there is none.
   */
  async _authRecord(uid) {
    try {
      return await this.auth.getUser(uid);
    } catch (err) {
      if (err.code === "auth/user-not-found") return null;
      throw err;
    }
  }

  /**
   * @param {string} uid
   * @param {!Object} record
   * @param {!Object} profile
   * @return {!Object}
   */
  _seed(uid, record, profile) {
    const created = Date.parse(record.metadata.creationTime || "") ||
      this.now();
    const name = typeof profile.name === "string" ?
      profile.name.slice(0, 120) : null;
    return {
      uid,
      displayName: name,
      nameLower: searchKey(name),
      emailMasked: maskEmail(record.email),
      emailLower: searchKey(record.email),
      createdAt: new Date(created),
      lastActiveAt: new Date(created),
      status: record.disabled ? "disabled" : "active",
      hasWorkoutPlan: false,
      schemaVersion: 1,
    };
  }

  /**
   * @param {string} uid
   * @param {{name: string, props: !Object}} event
   * @param {!Date} at
   * @return {!Object}
   */
  _eventDoc(uid, event, at) {
    return {
      uid,
      name: event.name,
      at,
      props: event.props || {},
      expireAt: new Date(at.getTime() + EVENT_RETENTION_DAYS * DAY_MS),
    };
  }

  /**
   * The `update()` fields for [event] against the current summary.
   * @param {!Object} current
   * @param {{name: string, props: !Object}} event
   * @param {!Date} at
   * @return {!Object}
   */
  _patchFields(current, event, at) {
    const {set, inc} = summaryPatch(event, at);
    // Triggers can arrive out of order; activity only moves forward.
    const last = toMillis(current.lastActiveAt);
    if (set.lastActiveAt && last != null && last > at.getTime()) {
      delete set.lastActiveAt;
      delete set.lastEvent;
    }
    if (event.name === AdminEvent.WORKOUT_PLAN_CREATED &&
        !current.workoutPlanCreatedAt) {
      set.workoutPlanCreatedAt = at;
    }
    const fields = Object.assign({}, set);
    for (const [k, v] of Object.entries(inc)) {
      if (v !== 0) fields[k] = this.FieldValue.increment(v);
    }
    fields.updatedAt = this.FieldValue.serverTimestamp();
    return fields;
  }

  /**
   * Per-day counts of [names] for the last [days] local days, oldest first.
   * @param {(number|undefined)} offset
   * @param {number} days
   * @param {!Array<string>} names
   * @return {!Promise<!Array<!Object>>}
   */
  async _dailySeries(offset, days, names) {
    const events = this.db.collection(EVENTS);
    const now = this.now();
    const out = [];
    for (let i = days - 1; i >= 0; i--) {
      const start = localDayStart(now, offset, i);
      const end = new Date(start.getTime() + DAY_MS);
      out.push({start, end});
    }
    const rows = await Promise.all(out.map(async ({start, end}) => {
      const values = await Promise.all(names.map((n) => count(events
          .where("name", "==", n)
          .where("at", ">=", start)
          .where("at", "<", end))));
      return Object.assign({day: start.toISOString()},
          Object.fromEntries(names.map((n, i) => [n, values[i]])));
    }));
    return rows;
  }

  /**
   * @param {!Array<string>} uids
   * @return {!Promise<!Map<string, string>>}
   */
  async _displayNames(uids) {
    const unique = [...new Set(uids.filter((u) => typeof u === "string"))];
    if (!unique.length) return new Map();
    const refs = unique.map((u) => this.db.collection(USERS).doc(u));
    const snaps = await this.db.getAll(...refs);
    const out = new Map();
    for (const s of snaps) {
      if (s.exists && s.get("displayName")) out.set(s.id, s.get("displayName"));
    }
    return out;
  }
}

/**
 * @param {!Object} query
 * @return {!Promise<number>}
 */
async function count(query) {
  const snap = await query.count().get();
  return snap.data().count;
}

/**
 * @param {!Object} query
 * @param {!Object} spec
 * @return {!Promise<!Object>}
 */
async function aggregate(query, spec) {
  const snap = await query.aggregate(spec).get();
  return snap.data();
}

/**
 * @param {!Object} a An aggregate result.
 * @return {!Object} The same keys, nulls as 0.
 */
function numbers(a) {
  const out = {};
  for (const [k, v] of Object.entries(a)) out[k] = Number.isFinite(v) ? v : 0;
  return out;
}

/**
 * @param {*} uid
 * @return {string}
 */
function requireUid(uid) {
  if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new AdminError("invalid-argument", "That isn't an account id.");
  }
  return uid;
}

/**
 * @param {*} s An Auth metadata date string.
 * @return {?string}
 */
function isoOf(s) {
  const ms = Date.parse(s || "");
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

module.exports = {AdminService, AdminError, ACTIVITY_NAMES};
