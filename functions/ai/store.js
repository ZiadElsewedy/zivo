/**
 * `FirestoreStore` — the only file besides `index.js` that touches
 * Firestore. Implements the read/persistence seam the gateway
 * (`functions/ai/gateway.js`) and tool registry (`functions/ai/tools.js`)
 * depend on, using the Admin SDK (which bypasses security rules, so this is
 * always `uid`-scoped explicitly). Field names mirror the client
 * repositories exactly (the `FirestoreXRepository` classes under
 * `lib/features/`).
 */

const {Timestamp} = require("firebase-admin/firestore");

/**
 * `Timestamp` field `value` converted to a `Date`, or null.
 * @param {*} value
 * @return {?Date}
 */
function toDate(value) {
  return value instanceof Timestamp ? value.toDate() : null;
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
   * @return {!Promise<!Array<Object>>}
   */
  async listTasks(uid) {
    const snap = await this._user(uid).collection("tasks").get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        title: d.title || "",
        done: !!d.done,
        priority: !!d.priority,
        due: toDate(d.due),
      };
    });
  }

  /**
   * @param {string} uid
   * @param {{fromMs: number, toMs: number}} range
   * @return {!Promise<!Array<Object>>}
   */
  async listSchedule(uid, range) {
    const snap = await this._user(uid)
        .collection("schedule")
        .where("start", ">=", Timestamp.fromMillis(range.fromMs))
        .where("start", "<", Timestamp.fromMillis(range.toMs))
        .get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        title: d.title || "",
        start: toDate(d.start),
        end: toDate(d.end),
        location: d.location || null,
        label: d.label || null,
      };
    });
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
   * @return {!Promise<!Array<Object>>}
   */
  async listUniversity(uid) {
    const snap = await this._user(uid).collection("universityItems").get();
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        title: d.title || "",
        type: d.type || "assignment",
        due: toDate(d.due),
        courseName: d.courseName || null,
        done: !!d.done,
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
   * Case-insensitive substring match over note bodies — Firestore has no
   * native substring query, so this fetches the (personal-scale) note set
   * and filters in memory, mirroring `search_notes`'s "naive search" scope.
   * @param {string} uid
   * @param {string} query
   * @return {!Promise<!Array<Object>>}
   */
  async searchNotes(uid, query) {
    const snap = await this._user(uid).collection("notes").get();
    const lowerQuery = query.toLowerCase();
    return snap.docs
        .map((doc) => {
          const d = doc.data();
          return {
            id: doc.id,
            title: d.title || null,
            body: d.body || "",
            updatedAt: toDate(d.updatedAt),
          };
        })
        .filter((n) => n.body.toLowerCase().includes(lowerQuery));
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
    await ref.set({
      role: message.role,
      content: message.content,
      createdAt: Timestamp.fromDate(message.createdAt),
      schemaVersion: 1,
    });
    return ref.id;
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
          return {
            role: d.role,
            content: d.content,
            createdAt: toDate(d.createdAt) || new Date(0),
          };
        })
        .reverse();
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
    snap.forEach((doc) => {
      const d = doc.data();
      turns += 1;
      tokens += (d.tokensIn || 0) + (d.tokensOut || 0);
    });
    return {turns, tokens};
  }
}

module.exports = {FirestoreStore};
