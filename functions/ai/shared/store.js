/**
 * `FirestoreStore` — the only file besides `index.js` that touches
 * Firestore. Implements the read/persistence seam the gateway
 * (`functions/ai/gateway.js`) and tool registry (`functions/ai/tools/read.js`)
 * depend on, using the Admin SDK (which bypasses security rules, so this is
 * always `uid`-scoped explicitly). Field names mirror the client
 * repositories exactly (the `FirestoreXRepository` classes under
 * `lib/features/`).
 */

const {Timestamp, FieldValue} = require("firebase-admin/firestore");
const {dailyCapUsageFor} = require("../chat/usage");
const {applyRotationChange} = require("../tools/workout_rotation");

/**
 * `Timestamp` field `value` converted to a `Date`, or null.
 * @param {*} value
 * @return {?Date}
 */
function toDate(value) {
  return value instanceof Timestamp ? value.toDate() : null;
}

/**
 * Midnight at the start of the 'yyyy-MM-dd' day `dayKey` names.
 * @param {string} dayKey
 * @return {!Date}
 */
function startOfDayFor(dayKey) {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(y, m - 1, d);
}

/** The Admin-SDK-backed `store` seam for the `aiChat` gateway. */
class FirestoreStore {
  /**
   * @param {!Object} db A `firebase-admin/firestore` `Firestore` instance.
   */
  constructor(db) {
    this.db = db;
  }

  /**
   * @param {string} uid
   * @return {!Object} The `users/{uid}` document reference.
   */
  _user(uid) {
    return this.db.collection("users").doc(uid);
  }

  /**
   * @param {string} uid
   * @param {{fromMs: number, toMs: number}} range
   * @return {!Promise<!Array<Object>>}
   */
  async listExpenses(uid, range) {
    const snap = await this._user(uid)
        .collection("expenses")
        .where("spentAt", ">=", Timestamp.fromMillis(range.fromMs))
        .where("spentAt", "<", Timestamp.fromMillis(range.toMs))
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        amountMinor: d.amountMinor || 0,
        currency: d.currency || "",
        category: d.category || "other",
        note: d.note || null,
        spentAt: toDate(d.spentAt),
      };
    });
  }

  /**
   * @param {string} uid
   * @param {{fromMs: number, toMs: number}} range
   * @return {!Promise<!Array<Object>>}
   */
  async listWorkouts(uid, range) {
    const snap = await this._user(uid)
        .collection("workouts")
        .where("performedAt", ">=", Timestamp.fromMillis(range.fromMs))
        .where("performedAt", "<", Timestamp.fromMillis(range.toMs))
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        title: d.title || "",
        performedAt: toDate(d.performedAt),
        durationMinutes: d.durationMinutes || null,
        exercises: d.exercises || [],
      };
    });
  }

  /**
   * The user's live/completed workout SESSIONS — the rich, per-set record in
   * `users/{uid}/workoutSessions` (not the lossy flat `workouts` log). This is
   * what the workout analytics engine (`../analytics/workout_analytics.js`)
   * reasons over, so the AI sees the real sets the user performed rather than a
   * single
   * collapsed reps/weight per exercise. Ranged by `startedAt`; pass no range
   * to read the whole history (the analytics windows filter internally).
   *
   * Field names mirror `FirestoreWorkoutSessionRepository` exactly.
   * @param {string} uid
   * @param {{fromMs: number, toMs: number}=} range
   * @return {!Promise<!Array<Object>>}
   */
  async listWorkoutSessions(uid, range) {
    let query = this._user(uid).collection("workoutSessions");
    if (range) {
      query = query
          .where("startedAt", ">=", Timestamp.fromMillis(range.fromMs))
          .where("startedAt", "<", Timestamp.fromMillis(range.toMs));
    }
    const snap = await query.get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        planId: d.planId || "",
        dayId: d.dayId || "",
        dayLabel: d.dayLabel || "",
        status: d.status || "active",
        startedAt: toDate(d.startedAt),
        completedAt: toDate(d.completedAt),
        pausedAccumMs: typeof d.pausedAccumMs === "number" ? d.pausedAccumMs : 0,
        // Duration provenance and the user's own correction — the coach must
        // reason from the same figure the app shows, and must not be handed a
        // duration the app has already decided it does not believe.
        durationSource: d.durationSource || "measured",
        correctedDurationMinutes:
          typeof d.correctedDurationMinutes === "number" ?
            d.correctedDurationMinutes :
            null,
        exercises: (d.exercises || []).map((e) => ({
          id: e.id || "",
          exerciseId: e.exerciseId || "",
          name: e.name || "",
          muscleGroup: e.muscleGroup || null,
          restSeconds: e.restSeconds || 0,
          sets: (e.sets || []).map((s) => ({
            id: s.id || "",
            actualReps: typeof s.actualReps === "number" ? s.actualReps : null,
            actualWeightKg:
              typeof s.actualWeightKg === "number" ? s.actualWeightKg : null,
            rpe: typeof s.rpe === "number" ? s.rpe : null,
            type: s.type || "working",
            // Migrate a pre-outcome doc's legacy `done` bool, matching the
            // client repo's `_outcomeFromMap`.
            outcome: s.outcome || (s.done === true ? "completed" : "pending"),
          })),
        })),
      };
    });
  }

  /**
   * The active `workoutPlans` doc for `uid`, resolved EXACTLY the way the app's
   * `FirestoreWorkoutPlanRepository._resolveActive` does — so the coach's
   * plan-adherence read and the Analysis screen agree on which split is active:
   *   1. the split named by the `workoutMeta/active` pointer (`activeSplitId`),
   *   2. else the first split with status 'active',
   *   3. else the oldest split (splits are ordered createdAt-ascending).
   * Returns only the fields adherence needs (days → exercises → id/name),
   * or null when there is no plan.
   * @param {string} uid
   * @return {!Promise<?Object>}
   */
  async getActiveWorkoutPlan(uid) {
    const snap = await this._user(uid)
        .collection("workoutPlans")
        .orderBy("createdAt")
        .get();
    if (snap.empty) return null;

    const plans = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        name: d.name || "",
        status: d.status || "active",
        // The `order` of the day that's up next — the rotation's "today".
        cycleCursor: typeof d.cycleCursor === "number" ? d.cycleCursor : 0,
        days: (d.days || []).map((day) => ({
          id: day.id || "",
          slot: day.slot || "",
          label: day.label || "",
          order: typeof day.order === "number" ? day.order : 0,
          exercises: (day.exercises || []).map((e) => ({
            id: e.id || "",
            name: e.name || "",
            muscleGroup: e.muscleGroup || null,
            order: typeof e.order === "number" ? e.order : 0,
          })),
        })),
      };
    });

    let pointerId = null;
    try {
      const pointerSnap = await this._user(uid)
          .collection("workoutMeta")
          .doc("active")
          .get();
      const raw = pointerSnap.exists ? pointerSnap.data().activeSplitId : null;
      pointerId = typeof raw === "string" && raw.length > 0 ? raw : null;
    } catch (_) {
      // The pointer is optional (same as the client): a read failure just
      // falls through to the active-status / oldest resolution below.
      pointerId = null;
    }

    if (pointerId) {
      const byPointer = plans.find((p) => p.id === pointerId);
      if (byPointer) return byPointer;
    }
    const active = plans.find((p) => p.status === "active");
    return active || plans[0];
  }

  /**
   * Applies a confirmed rotation change (`change_workout_day`: a swap, or a
   * skip onto another day) to the split `planId`, in a transaction over the
   * RAW doc — so every exercise and set on every day is written back exactly
   * as it was, and a plan edited since the proposal is refused rather than
   * overwritten (`../tools/workout_rotation.js` `applyRotationChange`).
   * @param {string} uid
   * @param {string} planId
   * @param {{mode: string, dueDayId: string, targetDayId: string}} change
   * @return {!Promise<void>}
   */
  async updateWorkoutRotation(uid, planId, change) {
    const ref = this._user(uid).collection("workoutPlans").doc(planId);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new Error("That split doesn't exist any more.");
      const d = snap.data();
      const next = applyRotationChange(
          {days: d.days || [], cycleCursor: d.cycleCursor}, change);
      tx.update(ref, {
        days: next.days,
        cycleCursor: next.cycleCursor,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  /**
   * The active `dietPlans` doc for `uid` (mirroring the client's "most
   * recently created plan with status active" resolution), or null.
   * @param {string} uid
   * @return {!Promise<?Object>}
   */
  async getActiveDietPlan(uid) {
    const snap = await this._user(uid)
        .collection("dietPlans")
        .orderBy("createdAt", "desc")
        .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if (d.status === "active") {
        return {
          id: doc.id,
          name: d.name || "",
          status: d.status,
          days: d.days || [],
        };
      }
    }
    return null;
  }

  /**
   * Overwrites the `days` field of an active `dietPlans` doc in place —
   * `replace_meal_item`'s confirm write. Deliberately narrower than
   * `FirestoreDietRepository.savePlan`'s client-side write: saving an ACTIVE
   * plan there archives whatever was active before (correct for creating or
   * replacing a whole plan), which is wrong here — this is tweaking one item
   * of the plan that is ALREADY active, not proposing a new one. Firestore has
   * no per-element array update, so the whole mutated `days` array is written
   * back; nothing else on the doc is touched.
   * @param {string} uid
   * @param {string} planId
   * @param {!Array<Object>} days The plan's `days`, with the one item already
   *   replaced in place by the caller.
   * @return {!Promise<void>}
   */
  async savePlanDays(uid, planId, days) {
    await this._user(uid).collection("dietPlans").doc(planId).update({days});
  }

  /**
   * The user's nutrition targets (`dietTargets/current`), or null when they
   * haven't set any.
   *
   * Null is a real answer, not a failure: ZIVO never invents a target, so the
   * coach has to be able to say "you haven't set one" rather than quietly
   * treating the plan's own total as a goal the user chose. A document that
   * can't be read as a real target (no goal, no usable calorie figure) is
   * reported the same way, for the same reason.
   * @param {string} uid
   * @return {!Promise<?Object>}
   */
  async getDietTargets(uid) {
    const snap = await this._user(uid)
        .collection("dietTargets")
        .doc("current")
        .get();
    if (!snap.exists) return null;
    const d = snap.data() || {};
    const calories = typeof d.calories === "number" && d.calories > 0 ?
      Math.round(d.calories) : null;
    if (!d.goal || calories === null) return null;
    const num = (v) =>
      typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
    return {
      goal: String(d.goal),
      calories,
      proteinG: num(d.proteinG),
      carbsG: num(d.carbsG),
      fatG: num(d.fatG),
      source: typeof d.source === "string" ? d.source : "manual",
    };
  }

  /**
   * The user's stored body data, or null when they haven't given it.
   *
   * Height, sex and activity are all required: two out of three cannot
   * produce a maintenance figure, and a profile that silently defaulted the
   * third would put a number nobody chose underneath every piece of coaching.
   * Weight is deliberately NOT here — it lives in `bodyWeightEntries`, which
   * is where the user actually keeps it.
   * @param {string} uid
   * @return {!Promise<?Object>}
   */
  async getBodyProfile(uid) {
    const snap = await this._user(uid)
        .collection("bodyProfile")
        .doc("current")
        .get();
    if (!snap.exists) return null;
    const d = snap.data() || {};
    const heightCm = typeof d.heightCm === "number" ? d.heightCm : null;
    if (heightCm === null || heightCm < 100 || heightCm > 250) return null;
    if (d.sex !== "male" && d.sex !== "female") return null;
    const activity = typeof d.activity === "string" ? d.activity : null;
    if (!activity) return null;
    const stated = typeof d.statedMaintenanceKcal === "number" ?
      Math.round(d.statedMaintenanceKcal) : null;
    return {
      heightCm,
      sex: d.sex,
      activity,
      statedMaintenanceKcal:
        stated !== null && stated >= 800 && stated <= 10000 ? stated : null,
    };
  }

  /**
   * Every logged weigh-in, oldest first. The calibration needs the span, not
   * just the latest reading.
   *
   * The collection is `bodyWeightEntries` — the name the client writes
   * (`FirestoreBodyWeightRepository`) and the one the rules declare. This read
   * used to say `bodyWeights`, which is a collection nothing has ever written:
   * it returned an empty array forever, and because every consumer downstream
   * treats "no weigh-ins" as a legitimate state, it failed SILENTLY. The coach
   * lost its measured-maintenance calibration and its current weight, and fell
   * back to estimates without anything looking wrong.
   * @param {string} uid
   * @return {!Promise<!Array<{weightKg: number, loggedAtMs: number}>>}
   */
  async listBodyWeights(uid) {
    const snap = await this._user(uid).collection("bodyWeightEntries").get();
    return snap.docs
        .map((doc) => {
          const d = doc.data() || {};
          const weightKg = typeof d.weightKg === "number" ? d.weightKg : null;
          const at = d.loggedAt;
          const loggedAtMs = at && typeof at.toMillis === "function" ?
            at.toMillis() : null;
          if (weightKg === null || loggedAtMs === null) return null;
          return {weightKg, loggedAtMs};
        })
        .filter(Boolean)
        .sort((a, b) => a.loggedAtMs - b.loggedAtMs);
  }

  /**
   * The user's sleep nights (`sleepNights/{yyyy-MM-dd}`), each reduced to what
   * the readiness call needs: the sleep-day, asleep minutes (main span less its
   * interruptions — mirrors `SleepSession.asleepDuration`), and the night's
   * snapshotted target duration. Nights with no `main` are dropped (no data).
   * Newest first. Read-only; only `get_readiness` uses it today.
   * @param {string} uid
   * @return {!Promise<!Array<{sleepDayMs: number, asleepMinutes: number,
   *   targetDurationMinutes: (number|null)}>>}
   */
  async listSleepNights(uid) {
    const snap = await this._user(uid).collection("sleepNights").get();
    const spanMinutes = (map) => {
      const start = toDate(map.startAt);
      const end = toDate(map.endAt);
      if (!start || !end) return null;
      let ms = end.getTime() - start.getTime();
      for (const raw of Array.isArray(map.interruptions) ?
        map.interruptions : []) {
        const iStart = toDate(raw.startAt);
        const iEnd = toDate(raw.endAt);
        if (iStart && iEnd) ms -= (iEnd.getTime() - iStart.getTime());
      }
      return ms <= 0 ? 0 : Math.round(ms / 60000);
    };
    return snap.docs
        .map((doc) => {
          const d = doc.data() || {};
          const main = d.main;
          if (!main || typeof main !== "object") return null;
          const asleepMinutes = spanMinutes(main);
          if (asleepMinutes === null) return null;
          const sleepDay = toDate(d.sleepDay);
          const targets = d.targets;
          const targetDurationMinutes = targets &&
            typeof targets.durationMinutes === "number" ?
            targets.durationMinutes : null;
          return {
            sleepDayMs: sleepDay ? sleepDay.getTime() : null,
            asleepMinutes,
            targetDurationMinutes,
          };
        })
        .filter((n) => n && n.sleepDayMs !== null)
        .sort((a, b) => b.sleepDayMs - a.sleepDayMs);
  }

  /**
   * The account profile's date of birth in ms, or null. Age is derived from
   * it at the moment of use — a stored integer age is wrong within a year of
   * being written.
   * @param {string} uid
   * @return {!Promise<?number>}
   */
  async getDateOfBirthMs(uid) {
    const snap = await this._user(uid).get();
    if (!snap.exists) return null;
    const dob = (snap.data() || {}).dateOfBirth;
    return dob && typeof dob.toMillis === "function" ? dob.toMillis() : null;
  }

  /**
   * The user's food log for one day — what they actually recorded eating.
   *
   * This is the consumption ledger. An entry is either something the user
   * logged (`origin: 'logged'`) or something materialised from a planned meal
   * they ticked (`origin: 'plannedMeal'`), and the difference matters: "you
   * ate 1,850 kcal" and "the plan values what you ticked at 1,850" are
   * different claims. An EMPTY log means nothing was recorded that day, not
   * that nothing was eaten.
   * @param {string} uid
   * @param {string} dayKey
   * @return {!Promise<!Array<Object>>}
   */
  async listFoodLogs(uid, dayKey) {
    const snap = await this._user(uid)
        .collection("foodLogs")
        .where("dayKey", "==", dayKey)
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
      return {
        id: doc.id,
        foodId: d.foodId || "",
        foodName: d.foodName || "",
        quantity: num(d.quantity),
        unit: d.unit || "g",
        grams: num(d.grams),
        kcal: Math.round(num(d.kcal)),
        proteinG: num(d.proteinG),
        carbsG: num(d.carbsG),
        fatG: num(d.fatG),
        source: d.source || "dietPlan",
        sourceRef: d.sourceRef || "",
        origin: d.origin === "logged" ? "logged" : "plannedMeal",
        estimated: d.estimated === true,
        mealId: d.mealId || null,
        loggedAt: toDate(d.loggedAt),
      };
    });
  }

  /**
   * Food-log entries across a range of days, inclusive.
   *
   * `dayKey` is a sortable 'yyyy-MM-dd' string, so this is a single-field
   * range query — one read for a whole week, and no composite index.
   * @param {string} uid
   * @param {string} fromDayKey
   * @param {string} toDayKey
   * @return {!Promise<!Array<Object>>}
   */
  async listFoodLogRange(uid, fromDayKey, toDayKey) {
    const snap = await this._user(uid)
        .collection("foodLogs")
        .where("dayKey", ">=", fromDayKey)
        .where("dayKey", "<=", toDayKey)
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        dayKey: d.dayKey || "",
        kcal: Math.round(typeof d.kcal === "number" ? d.kcal : 0),
      };
    });
  }

  /**
   * @param {string} uid
   * @param {string} dayKey
   * @return {!Promise<!Array<Object>>}
   */
  async listDietEntries(uid, dayKey) {
    const snap = await this._user(uid)
        .collection("dietEntries")
        .where("dayKey", "==", dayKey)
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {mealId: d.mealId || "", eaten: !!d.eaten};
    });
  }

  /**
   * Upserts the eaten-toggle for one meal on one day, mirroring the client's
   * `FirestoreDietRepository.setMealEaten` write exactly (same doc id
   * `dietEntries/{dayKey}__{mealId}`, same fields, merge) so either side's
   * writes are indistinguishable in Firestore.
   * @param {string} uid
   * @param {string} dayKey 'yyyy-MM-dd' (`dayKeyFor`)
   * @param {string} mealId
   * @param {boolean} eaten
   * @return {!Promise<void>}
   */
  async setDietEntry(uid, dayKey, mealId, eaten) {
    const now = FieldValue.serverTimestamp();
    await this._user(uid)
        .collection("dietEntries")
        .doc(`${dayKey}__${mealId}`)
        .set({
          dayKey,
          date: Timestamp.fromDate(startOfDayFor(dayKey)),
          mealId,
          eaten,
          schemaVersion: 1,
          createdAt: now,
          updatedAt: now,
        }, {merge: true});
  }

  /**
   * @param {string} uid
   * @param {string} conversationId
   * @param {{role: string, content: string, createdAt: !Date}} message
   * @return {!Promise<string>} The new message id.
   */
  async appendMessage(uid, conversationId, message) {
    const ref = this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .doc();
    const data = {
      role: message.role,
      content: message.content,
      createdAt: Timestamp.fromDate(message.createdAt),
      schemaVersion: 1,
    };
    // Client-generated idempotency key (ADR: chat turn dedup). Persisted on
    // both the user and assistant messages of a turn so a client retry that
    // races a slow-but-successful first attempt can be detected and served
    // idempotently instead of duplicating the turn.
    if (message.clientTurnId) {
      data.clientTurnId = message.clientTurnId;
    }
    // The read tools the turn ran to produce this reply (`{tool, status}`,
    // names only — never input or result), so the app can draw the activity
    // timeline above the reply on reload, not just while it streams.
    // A `{kind:'fallback', from, to}` entry records that the active model
    // was unavailable and the turn continued on the other one (model keys).
    if (Array.isArray(message.activity) && message.activity.length) {
      data.activity = message.activity.map((a) => a.kind === "fallback" ?
        {kind: "fallback", from: String(a.from), to: String(a.to)} :
        {tool: String(a.tool), status: a.status === "error" ? "error" : "ok"});
    }
    // An action_proposal message (ADR-003) carries the pending action the
    // client renders as a confirmation card. Its `status` mirrors the pending
    // action's lifecycle (pending → applied/cancelled/expired) so the card
    // reflects the true server state — including on reopen and however it was
    // resolved (button tap or otherwise) — not just an optimistic client flag.
    // A user message that answers a question card carries the structured
    // pick `{requestId, value}` — the answer itself, not its label.
    // What the coach said before a card (`../chat/actions.js` turnFields) —
    // the lead-in the app shows above the proposal / beside the options.
    if (typeof message.preface === "string" && message.preface) {
      data.preface = message.preface.slice(0, 4000);
    }
    // The turn's context ledger (`../chat/context_ledger.js`): the lookups
    // it already ran, so the NEXT turn can reuse them. Server-written only
    // (the messages rule is read-only to the client), read back by
    // getRecentMessages.
    if (message.context && Array.isArray(message.context.entries)) {
      data.context = message.context;
    }
    // A confirm/cancel echo names the proposal it resolves (`actions.js`).
    if (message.resultOf) data.resultOf = String(message.resultOf);
    if (message.choice && message.choice.requestId) {
      data.choice = {
        requestId: String(message.choice.requestId),
        value: String(message.choice.value),
      };
    }
    if (message.kind) {
      data.kind = message.kind;
      // A question card's id — the client answers it by this, and the server
      // looks it up by it (`getChoiceRequest`). Without it the app can't
      // render the card at all and falls back to a plain text bubble.
      if (message.requestId) data.requestId = message.requestId;
      // Server-side resolution of a choice card (option value → the verified
      // change choosing it means). Written only here, by the gateway; the
      // messages rule makes it read-only to the client.
      if (message.bindings) data.bindings = message.bindings;
      data.actionId = message.actionId || null;
      data.actionKind = message.actionKind || null;
      data.fields = message.fields || null;
      data.status = message.status || "pending";
      // When the pending action's TTL passes, the client renders the card as
      // expired from this even before a confirm attempt flips `status`.
      data.expiresAt = message.expiresAt ?
        Timestamp.fromDate(message.expiresAt) : null;
    }
    await ref.set(data);
    return ref.id;
  }

  /**
   * The id of the user's most recently active conversation (mirroring the
   * client's `latestConversation` ordering), or null when they have none —
   * the coach report's delivery target.
   * @param {string} uid
   * @return {!Promise<?string>}
   */
  async latestConversationId(uid) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .orderBy("updatedAt", "desc")
        .limit(1)
        .get();
    return snap.docs.length > 0 ? snap.docs[0].id : null;
  }

  /**
   * Creates `conversationId` if missing, else bumps `updatedAt`.
   * @param {string} uid
   * @param {string} conversationId
   * @param {{title: string, createdAt: !Date, updatedAt: !Date}} fields
   * @return {!Promise<void>}
   */
  async touchConversation(uid, conversationId, fields) {
    const ref = this._user(uid)
        .collection("aiConversations")
        .doc(conversationId);
    const snap = await ref.get();
    if (snap.exists) {
      await ref.update({updatedAt: Timestamp.fromDate(fields.updatedAt)});
      return;
    }
    await ref.set({
      title: fields.title,
      createdAt: Timestamp.fromDate(fields.createdAt),
      updatedAt: Timestamp.fromDate(fields.updatedAt),
      schemaVersion: 1,
    });
  }

  /**
   * @param {string} uid
   * @param {string} conversationId
   * @param {number} limit
   * @return {!Promise<!Array<Object>>} Oldest-first.
   */
  async getRecentMessages(uid, conversationId, limit) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => {
          const d = doc.data();
          const m = {
            role: d.role,
            content: d.content,
            createdAt: toDate(d.createdAt) || new Date(0),
          };
          // A card's structure travels with it, so the next turn can resolve
          // "option 2" against the options the user actually saw.
          if (d.kind) {
            m.kind = d.kind;
            m.fields = d.fields || null;
            m.status = d.status || null;
            if (d.selectedValue) m.selectedValue = d.selectedValue;
          }
          if (d.choice) m.choice = d.choice;
          if (d.preface) m.preface = d.preface;
          if (d.context) m.context = d.context;
          return m;
        })
        .reverse();
  }

  /**
   * The `choice_request` card with this `requestId`, or null — what a tapped
   * answer is resolved against (`../chat/choices.js`).
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} requestId
   * @return {!Promise<?Object>}
   */
  async getChoiceRequest(uid, conversationId, requestId) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .where("requestId", "==", requestId)
        .limit(1)
        .get();
    if (snap.empty) return null;
    const d = snap.docs[0].data();
    return {
      kind: d.kind || null,
      content: d.content || "",
      fields: d.fields || null,
      bindings: d.bindings || null,
      status: d.status || null,
      selectedValue: d.selectedValue || null,
    };
  }

  /**
   * Marks a question card answered with the option the user tapped, so it
   * renders settled on every device and can't be answered twice.
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} requestId
   * @param {string} value
   * @return {!Promise<void>}
   */
  async markChoiceAnswered(uid, conversationId, requestId, value) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .where("requestId", "==", requestId)
        .limit(1)
        .get();
    if (snap.empty) return;
    await snap.docs[0].ref.update({status: "answered", selectedValue: value});
  }

  /**
   * Finds an existing message written for a client turn id (chat turn
   * dedup). Returns {id, role, content} or null.
   *
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} clientTurnId
   * @return {!Promise<?{role: string, content: string}>}
   */
  async findMessageByClientTurnId(uid, conversationId, clientTurnId) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .where("clientTurnId", "==", clientTurnId)
        .orderBy("createdAt", "asc")
        .limit(10)
        .get();
    let assistant = null;
    let user = null;
    for (const doc of snap.docs) {
      const d = doc.data();
      if (d.role === "assistant" && !assistant) assistant = d;
      if (d.role === "user" && !user) user = d;
    }
    if (assistant) return {role: "assistant", content: assistant.content};
    if (user) return {role: "user", content: user.content};
    return null;
  }

  /**
   * @param {string} uid
   * @param {!Object} usageDoc
   * @return {!Promise<void>}
   */
  async logUsage(uid, usageDoc) {
    const ref = this._user(uid).collection("aiUsage").doc();
    await ref.set(
        Object.assign({}, usageDoc, {
          createdAt: Timestamp.fromDate(usageDoc.createdAt),
        }),
    );
  }

  /**
   * The user's AI settings doc (`users/{uid}/settings/ai`) — the model
   * selection (`provider`, a `../routing/models.js` key or `"auto"`) and the
   * reply style. Read server-side by the callables whose client call doesn't
   * carry the selection (imports, plan generation), so one choice in the app
   * steers every AI feature. Empty when unset or unreadable — a settings read
   * must never fail the AI request it only steers.
   * @param {string} uid
   * @return {!Promise<!Object>}
   */
  async getAiSettings(uid) {
    try {
      const snap = await this._user(uid).collection("settings").doc("ai").get();
      return (snap.exists && snap.data()) || {};
    } catch (_err) {
      return {};
    }
  }

  /**
   * Running totals for `dayKey`, used to enforce the per-day cap.
   * @param {string} uid
   * @param {string} dayKey
   * @return {!Promise<{turns: number, tokens: number}>}
   */
  async getTodayUsageTotals(uid, dayKey) {
    const snap = await this._user(uid)
        .collection("aiUsage")
        .where("dayKey", "==", dayKey)
        .get();
    let turns = 0;
    let tokens = 0;
    // What counts (chat only, failed turns free, cache reads excluded) is
    // `dailyCapUsageFor`'s rule — see `../chat/usage.js`.
    snap.forEach((doc) => {
      const counted = dailyCapUsageFor(doc.data());
      turns += counted.turns;
      tokens += counted.tokens;
    });
    return {turns, tokens};
  }

  // --- V2 mutations (ADR-003): pending actions + confirmed entity writes -----

  /**
   * @param {string} uid
   * @param {string} conversationId
   * @return {!Object} The `pendingActions` subcollection reference.
   */
  _pendingActions(uid, conversationId) {
    return this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("pendingActions");
  }

  /**
   * Persists a proposed-but-unconfirmed action, keyed by `actionId`.
   * @param {string} uid
   * @param {string} conversationId
   * @param {!Object} action
   * @return {!Promise<void>}
   */
  async createPendingAction(uid, conversationId, action) {
    await this._pendingActions(uid, conversationId).doc(action.actionId).set({
      kind: action.kind,
      tool: action.tool,
      input: action.input,
      summary: action.summary,
      fields: action.fields,
      status: action.status,
      createdAt: Timestamp.fromDate(action.createdAt),
      expiresAt: Timestamp.fromDate(action.expiresAt),
      schemaVersion: 1,
    });
  }

  /**
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} actionId
   * @return {!Promise<?Object>} The action (timestamps as `Date`s), or null.
   */
  async getPendingAction(uid, conversationId, actionId) {
    const snap = await this._pendingActions(uid, conversationId)
        .doc(actionId).get();
    if (!snap.exists) return null;
    const d = snap.data();
    return {
      actionId,
      kind: d.kind,
      tool: d.tool,
      input: d.input || {},
      summary: d.summary || "",
      fields: d.fields || {},
      status: d.status || "pending",
      createdAt: toDate(d.createdAt),
      expiresAt: toDate(d.expiresAt),
    };
  }

  /**
   * The oldest still-`pending`, unexpired action in the conversation, or null.
   * Used to block a second proposal while one already awaits the user (ADR-003:
   * one pending action at a time), which prevents a duplicate entity write when
   * the model re-proposes. Equality-only on `status` (no composite index).
   * @param {string} uid
   * @param {string} conversationId
   * @param {!Date} nowDate
   * @return {!Promise<?Object>}
   */
  async getActivePendingAction(uid, conversationId, nowDate) {
    const snap = await this._pendingActions(uid, conversationId)
        .where("status", "==", "pending").get();
    const nowMs = (nowDate instanceof Date ? nowDate : new Date()).getTime();
    for (const doc of snap.docs) {
      const d = doc.data();
      const expiresAt = toDate(d.expiresAt);
      if (!expiresAt || expiresAt.getTime() > nowMs) {
        return {
          actionId: doc.id,
          kind: d.kind,
          summary: d.summary || "",
          status: d.status || "pending",
        };
      }
    }
    return null;
  }

  /**
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} actionId
   * @param {string} status 'applied' | 'cancelled' | 'expired'
   * @return {!Promise<void>}
   */
  async markPendingAction(uid, conversationId, actionId, status) {
    await this._pendingActions(uid, conversationId).doc(actionId).update({
      status,
      resolvedAt: FieldValue.serverTimestamp(),
    });
  }

  /**
   * Flips the `status` on the `action_proposal` message carrying `actionId`, so
   * the client's confirmation card reflects the resolution (applied/cancelled/
   * expired) on its next render and on reopen — regardless of how the action
   * was resolved. Equality-only on `actionId` (no composite index). A no-op if
   * the message is missing.
   * @param {string} uid
   * @param {string} conversationId
   * @param {string} actionId
   * @param {string} status
   * @return {!Promise<void>}
   */
  async markProposalMessage(uid, conversationId, actionId, status) {
    const snap = await this._user(uid)
        .collection("aiConversations")
        .doc(conversationId)
        .collection("messages")
        .where("actionId", "==", actionId)
        .limit(1)
        .get();
    if (snap.empty) return;
    await snap.docs[0].ref.update({status});
  }

  /**
   * Writes a confirmed expense (idempotent by `e.id`). Mirrors
   * `FirestoreExpenseRepository.add`.
   * @param {string} uid
   * @param {!Object} e
   * @return {!Promise<void>}
   */
  async createExpense(uid, e) {
    await this._user(uid).collection("expenses").doc(e.id).set({
      amountMinor: e.amountMinor,
      currency: e.currency,
      category: e.category,
      spentAt: e.spentAtIso ?
        Timestamp.fromDate(new Date(e.spentAtIso)) :
        FieldValue.serverTimestamp(),
      note: e.note || null,
      schemaVersion: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  /**
   * One expense doc by id (uid-scoped), or null. Field names mirror
   * `listExpenses` / the client `FirestoreExpenseRepository`.
   * @param {string} uid
   * @param {string} id
   * @return {!Promise<?Object>}
   */
  async getExpense(uid, id) {
    const snap = await this._user(uid).collection("expenses").doc(id).get();
    if (!snap.exists) return null;
    const d = snap.data();
    return {
      id: snap.id,
      amountMinor: d.amountMinor || 0,
      currency: d.currency || "",
      category: d.category || "other",
      note: d.note || null,
      spentAt: toDate(d.spentAt),
    };
  }

  /**
   * Edits an existing expense in place, mirroring the client
   * `FirestoreExpenseRepository.update`. Only the fields present in `patch`
   * change (a partial merge over the existing doc); `updatedAt` is always
   * bumped. Uses `.update()` (not `.set(..., {merge})`) so a race where the
   * doc was deleted between propose and confirm fails loudly rather than
   * resurrecting a half-populated expense.
   * @param {string} uid
   * @param {string} id
   * @param {!Object} patch amountMinor/currency/category/note/spentAtIso
   * @return {!Promise<void>}
   */
  async updateExpense(uid, id, patch) {
    const data = {updatedAt: FieldValue.serverTimestamp()};
    if (patch.amountMinor !== undefined) data.amountMinor = patch.amountMinor;
    if (patch.currency !== undefined) data.currency = patch.currency;
    if (patch.category !== undefined) data.category = patch.category;
    if (patch.note !== undefined) data.note = patch.note;
    if (patch.spentAtIso !== undefined) {
      data.spentAt = Timestamp.fromDate(new Date(patch.spentAtIso));
    }
    await this._user(uid).collection("expenses").doc(id).update(data);
  }

  /**
   * Deletes an expense by id, mirroring the client
   * `FirestoreExpenseRepository.remove`.
   * @param {string} uid
   * @param {string} id
   * @return {!Promise<void>}
   */
  async deleteExpense(uid, id) {
    await this._user(uid).collection("expenses").doc(id).delete();
  }

  /**
   * The user's own foods (`customFoods`) — everything the bundled USDA catalog
   * doesn't cover. Layered OVER the catalog when the coach resolves a food, so
   * the coach and the app agree on what the user's "Koshari" is worth. Field
   * names mirror `FirestoreDietRepository.saveCustomFood` /
   * `_customFoodFromDoc` exactly.
   * @param {string} uid
   * @return {!Promise<!Array<Object>>}
   */
  async listCustomFoods(uid) {
    const snap = await this._user(uid).collection("customFoods").get();
    return snap.docs
        .map((doc) => {
          const d = doc.data();
          const num = (v) =>
            (typeof v === "number" && Number.isFinite(v) ? v : 0);
          if (!d.name || typeof d.kcalPer100g !== "number") return null;
          return {
            id: doc.id,
            name: String(d.name),
            kcalPer100g: num(d.kcalPer100g),
            proteinPer100g: num(d.proteinPer100g),
            carbsPer100g: num(d.carbsPer100g),
            fatPer100g: num(d.fatPer100g),
            preparation: typeof d.preparation === "string" ?
              d.preparation : "unknown",
            portions: (Array.isArray(d.portions) ? d.portions : [])
                .filter((p) => p && typeof p.label === "string" &&
                  typeof p.grams === "number")
                .map((p) => ({label: p.label, grams: p.grams})),
            createdAt: toDate(d.createdAt),
          };
        })
        .filter((f) => f !== null);
  }

  /**
   * Saves one custom food (`create_custom_food`) — mirrors
   * `FirestoreDietRepository.saveCustomFood`'s field shape exactly (including
   * the empty `portions: []` and `schemaVersion: 1`), so a food the coach
   * saved is indistinguishable in Firestore, and in the app's own "My foods"
   * list, from one the user typed in by hand. `id` is the confirmed action's
   * id, so re-confirming overwrites the same doc rather than duplicating it.
   * @param {string} uid
   * @param {!Object} data `{id, name, kcalPer100g, proteinPer100g,
   *   carbsPer100g, fatPer100g, preparation}`.
   * @return {!Promise<void>}
   */
  async saveCustomFood(uid, data) {
    await this._user(uid).collection("customFoods").doc(data.id).set({
      name: data.name,
      kcalPer100g: data.kcalPer100g,
      proteinPer100g: data.proteinPer100g,
      carbsPer100g: data.carbsPer100g,
      fatPer100g: data.fatPer100g,
      preparation: data.preparation || "unknown",
      portions: [],
      schemaVersion: 1,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  /**
   * Writes food-log entries the coach logged on the user's behalf (`log_food`),
   * one batch so "two eggs and 100 g rice" lands whole or not at all. Mirrors
   * `FirestoreDietRepository.logFood` / `_entryToMap` field-for-field, so an
   * entry the coach wrote is indistinguishable in Firestore from one the app
   * wrote — and satisfies the tight `foodLogs` rule (the nutrition is stored,
   * not recomputed on read).
   *
   * Each entry's doc id is `${actionId}__${i}`, so re-confirming the same
   * pending action overwrites rather than duplicating.
   * @param {string} uid
   * @param {!Array<Object>} entries
   * @return {!Promise<void>}
   */
  async writeFoodLog(uid, entries) {
    if (!Array.isArray(entries) || entries.length === 0) return;
    const now = FieldValue.serverTimestamp();
    const collection = this._user(uid).collection("foodLogs");
    const batch = this.db.batch();
    for (const e of entries) {
      batch.set(collection.doc(e.id), {
        dayKey: e.dayKey,
        date: Timestamp.fromDate(startOfDayFor(e.dayKey)),
        loggedAt: now,
        foodId: e.foodId,
        foodName: e.foodName,
        quantity: e.quantity,
        unit: e.unit,
        grams: e.grams,
        kcal: Math.round(e.kcal),
        proteinG: e.proteinG,
        carbsG: e.carbsG,
        fatG: e.fatG,
        source: e.source,
        sourceRef: e.sourceRef,
        origin: e.origin,
        estimated: e.estimated === true,
        mealId: e.mealId || null,
        schemaVersion: 1,
      });
    }
    await batch.commit();
  }
}

module.exports = {FirestoreStore};
