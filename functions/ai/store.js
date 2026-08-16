/**
 * `FirestoreStore` — the only file besides `index.js` that touches
 * Firestore. Implements the read/persistence seam the gateway
 * (`functions/ai/gateway.js`) and tool registry (`functions/ai/tools.js`)
 * depend on, using the Admin SDK (which bypasses security rules, so this is
 * always `uid`-scoped explicitly). Field names mirror the client
 * repositories exactly (the `FirestoreXRepository` classes under
 * `lib/features/`).
 */

const {Timestamp, FieldValue} = require("firebase-admin/firestore");

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
    const data = {
      role: message.role,
      content: message.content,
      createdAt: Timestamp.fromDate(message.createdAt),
      schemaVersion: 1,
    };
    // An action_proposal message (ADR-003) carries the pending action the
    // client renders as a confirmation card.
    if (message.kind) {
      data.kind = message.kind;
      data.actionId = message.actionId || null;
      data.actionKind = message.actionKind || null;
      data.fields = message.fields || null;
    }
    await ref.set(data);
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
   * Writes a confirmed task. Doc id = `task.id` (the action id), so a
   * re-confirm overwrites identically (idempotent). Field shape mirrors
   * `FirestoreTaskRepository.add`.
   * @param {string} uid
   * @param {{id: string, title: string, dueIso: ?string, priority: boolean}} t
   * @return {!Promise<void>}
   */
  async createTask(uid, t) {
    await this._user(uid).collection("tasks").doc(t.id).set({
      title: t.title,
      due: t.dueIso ? Timestamp.fromDate(new Date(t.dueIso)) : null,
      priority: !!t.priority,
      done: false,
      schemaVersion: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
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
   * Writes a confirmed schedule event (idempotent by `ev.id`). Mirrors
   * `FirestoreScheduleRepository.add`.
   * @param {string} uid
   * @param {!Object} ev
   * @return {!Promise<void>}
   */
  async createEvent(uid, ev) {
    await this._user(uid).collection("schedule").doc(ev.id).set({
      title: ev.title,
      start: Timestamp.fromDate(new Date(ev.startIso)),
      end: ev.endIso ? Timestamp.fromDate(new Date(ev.endIso)) : null,
      location: ev.location || null,
      label: null,
      schemaVersion: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

module.exports = {FirestoreStore};
