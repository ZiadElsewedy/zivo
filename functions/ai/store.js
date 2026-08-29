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
    // An action_proposal message (ADR-003) carries the pending action the
    // client renders as a confirmation card. Its `status` mirrors the pending
    // action's lifecycle (pending → applied/cancelled/expired) so the card
    // reflects the true server state — including on reopen and however it was
    // resolved (button tap or otherwise) — not just an optimistic client flag.
    if (message.kind) {
      data.kind = message.kind;
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
          return {
            role: d.role,
            content: d.content,
            createdAt: toDate(d.createdAt) || new Date(0),
          };
        })
        .reverse();
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
}

module.exports = {FirestoreStore};
