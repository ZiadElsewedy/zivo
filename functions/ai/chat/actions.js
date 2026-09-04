/**
 * The confirm-gated WRITE use-cases (ADR-003 V2 / ADR-005): everything that
 * turns a proposed change into a durable Firestore write, and only ever after
 * the user taps Confirm.
 *
 *   persistProposal      — persist a validated mutating-tool call as a pending
 *                          action + the action_proposal card (NO entity write)
 *   confirmAction        — the user confirmed: write, mark applied, echo result
 *   cancelAction         — the user cancelled: mark cancelled, echo a note
 *   applyProposedAction  — the actual per-kind Firestore write (idempotent)
 *
 * The propose branch lives in `turn.js` (it's part of the turn loop); this
 * module owns the two entrypoints the app calls afterwards (`aiConfirmAction` /
 * `aiCancelAction`) and the shared write dispatch. Nothing here calls the model.
 */

const {randomUUID} = require("node:crypto");
const {dayKeyFor, resolveDietDay} = require("../dates");
const {mutatingToolsByName} = require("../mutations");
const {GatewayError, assertDocumentId} = require("./errors");

/**
 * Persists a validated mutating-tool call as a pending action and appends the
 * `action_proposal` assistant message the client renders as a confirmation
 * card. Performs NO entity write.
 *
 * @param {!Object} args
 * @param {!Object} args.store
 * @param {string} args.uid
 * @param {string} args.conversationId
 * @param {!Object} args.tool The mutating tool (has kind/summarize/fields).
 * @param {!Object} args.validated The tool's normalized, JSON-safe payload.
 * @param {function(): !Date} args.clock
 * @param {number} args.ttlMs Pending-action lifetime.
 * @return {!Promise<{actionId: string, summary: string, fields: !Object,
 *   kind: string}>}
 */
async function persistProposal({
  store, uid, conversationId, tool, validated, clock, ttlMs,
}) {
  const actionId = randomUUID();
  const createdAt = clock();
  const expiresAt = new Date(createdAt.getTime() + ttlMs);
  const summary = tool.summarize(validated);
  const fields = tool.fields(validated);

  await store.createPendingAction(uid, conversationId, {
    actionId,
    kind: tool.kind,
    tool: tool.name,
    input: validated,
    summary,
    fields,
    status: "pending",
    createdAt,
    expiresAt,
  });
  await store.appendMessage(uid, conversationId, {
    role: "assistant",
    kind: "action_proposal",
    content: summary,
    actionId,
    actionKind: tool.kind,
    fields,
    status: "pending",
    // Carried on the message so the client can render the card as expired once
    // the TTL passes, without waiting for a confirm attempt to flip the status.
    expiresAt,
    createdAt,
  });
  return {actionId, summary, fields, kind: tool.kind};
}

/**
 * Throws unless `mealId` is a real meal in the user's active plan on the
 * calendar day `dayKey` — the confirm-time half of the check `mark_meal_eaten`
 * already did at propose time.
 *
 * Doing it twice is deliberate. A proposal can wait up to an hour for a tap,
 * and the plan can be edited, replaced or deleted in that window; the write
 * itself is the last moment the reference can still be proven. Without it a
 * stale id creates a `dietEntries` doc pointing at a meal that no longer
 * exists — invisible in the app, and quietly wrong in every "meals eaten"
 * count that follows.
 *
 * The day is resolved from the day key alone (anchored at midday so no
 * timezone can shift it), which keeps this independent of whatever clock the
 * confirming request happens to carry.
 *
 * @param {!Object} store
 * @param {string} uid
 * @param {string} dayKey 'yyyy-MM-dd'
 * @param {string} mealId
 * @return {!Promise<void>}
 */
async function requireMealInPlan(store, uid, dayKey, mealId) {
  const plan = await store.getActiveDietPlan(uid);
  if (!plan) {
    throw new GatewayError(
        "failed-precondition",
        "There's no active diet plan any more, so that meal can't be marked.");
  }
  const day = resolveDietDay(plan.days || [], new Date(`${dayKey}T12:00:00Z`), 0);
  const meals = day && Array.isArray(day.meals) ? day.meals : [];
  if (!meals.some((m) => m && m.id === mealId)) {
    throw new GatewayError(
        "failed-precondition",
        "That meal isn't in your plan any more — the plan changed since I " +
        "suggested it. Ask me again and I'll use the current one.");
  }
}

/**
 * Executes a confirmed action's Firestore write through the `store` seam. The
 * entity's doc id is the `actionId`, so re-execution is idempotent.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Object} action A pending action loaded from the store.
 * @return {!Promise<void>}
 */
async function applyProposedAction(store, uid, action) {
  const id = action.actionId;
  const v = action.input || {};
  switch (action.kind) {
    case "create_expense":
      return store.createExpense(uid, {
        id, amountMinor: v.amountMinor, currency: v.currency,
        category: v.category, note: v.note, spentAtIso: v.spentAtIso,
      });
    case "edit_expense": {
      // Only the fields the model set are carried into the patch; the store
      // leaves everything else on the existing doc untouched.
      const patch = {};
      for (const k of
        ["amountMinor", "currency", "category", "note", "spentAtIso"]) {
        if (v[k] !== undefined) patch[k] = v[k];
      }
      return store.updateExpense(uid, v.expenseId, patch);
    }
    case "delete_expense":
      return store.deleteExpense(uid, v.expenseId);
    case "mark_meal_eaten": {
      // The entry doc is keyed by day+meal (not actionId), but re-confirming
      // converges on the same toggle either way — still idempotent in effect.
      //
      // `dayKey` was resolved in the USER's timezone at propose time and the
      // meal id proven against their plan then. Both are re-checked here: a
      // pending action can sit for an hour, and the plan may have been edited
      // or replaced in between. A pending action created before this shipped
      // carries only `dateIso`, hence the fallback.
      const key = v.dayKey ||
        dayKeyFor(v.dateIso ? new Date(v.dateIso) : new Date());
      await requireMealInPlan(store, uid, key, v.mealId);
      return store.setDietEntry(uid, key, v.mealId, v.eaten);
    }
    case "log_food": {
      // The nutrition was resolved and snapshotted into `entries` at propose
      // time (mutations.js `log_food.verify`), so there is nothing to re-check
      // here: unlike a plan meal, a logged food's figures are frozen the moment
      // they're computed and can't drift if the catalog is rebuilt. Each doc id
      // is derived from the actionId, so a double-confirm overwrites the same
      // rows rather than duplicating the meal.
      const entries = (v.entries || []).map((e, i) =>
        Object.assign({}, e, {id: `${id}__${i}`}));
      return store.writeFoodLog(uid, entries);
    }
    default:
      throw new GatewayError(
          "failed-precondition", `Unknown action kind: ${action.kind}.`);
  }
}

/**
 * The deterministic confirmed-result line for an action (ADR-003: no model
 * call on confirm).
 * @param {!Object} action
 * @return {string}
 */
function resultLineFor(action) {
  const tool = mutatingToolsByName.get(action.tool);
  return tool && typeof tool.result === "function" ?
    tool.result(action.input || {}) : "Done.";
}

/**
 * Executes a user-confirmed pending action (`aiConfirmAction`): re-validates
 * that it's still pending and unexpired, performs the write server-side keyed
 * by `actionId` (idempotent), marks it `applied`, and appends the deterministic
 * result message.
 *
 * @param {!Object} args
 * @param {!Object} args.store
 * @param {string} args.uid
 * @param {string} args.conversationId
 * @param {string} args.actionId
 * @param {(function(): !Date)|undefined} args.now
 * @return {!Promise<{status: string, assistantText: string, actionId: string}>}
 */
async function confirmAction({store, uid, conversationId, actionId, now}) {
  const clock = now || (() => new Date());
  assertDocumentId(conversationId, "conversationId");
  assertDocumentId(actionId, "actionId");

  const action = await store.getPendingAction(uid, conversationId, actionId);
  if (!action) {
    throw new GatewayError(
        "not-found", "That suggestion is no longer available.");
  }
  if (action.status === "applied") {
    // Idempotent: a double-confirm returns the same result without re-writing.
    return {status: "already-applied", assistantText: resultLineFor(action),
      actionId};
  }
  if (action.status !== "pending") {
    throw new GatewayError(
        "failed-precondition", "That suggestion was already handled.");
  }
  if (action.expiresAt && action.expiresAt.getTime() <= clock().getTime()) {
    await store.markPendingAction(uid, conversationId, actionId, "expired");
    await store.markProposalMessage(uid, conversationId, actionId, "expired");
    throw new GatewayError(
        "failed-precondition", "That suggestion expired — ask again.");
  }

  await applyProposedAction(store, uid, action);
  await store.markPendingAction(uid, conversationId, actionId, "applied");
  await store.markProposalMessage(uid, conversationId, actionId, "applied");
  const resultText = resultLineFor(action);
  await store.appendMessage(uid, conversationId, {
    role: "assistant",
    content: resultText,
    createdAt: clock(),
  });
  return {status: "applied", assistantText: resultText, actionId};
}

/**
 * Cancels a pending action (`aiCancelAction`): marks it `cancelled` and appends
 * a brief note. Idempotent no-op for anything already resolved. Never writes an
 * entity.
 *
 * @param {!Object} args
 * @param {!Object} args.store
 * @param {string} args.uid
 * @param {string} args.conversationId
 * @param {string} args.actionId
 * @param {(function(): !Date)|undefined} args.now
 * @return {!Promise<{status: string, assistantText: ?string,
 *   actionId: string}>}
 */
async function cancelAction({store, uid, conversationId, actionId, now}) {
  const clock = now || (() => new Date());
  assertDocumentId(conversationId, "conversationId");
  assertDocumentId(actionId, "actionId");

  const action = await store.getPendingAction(uid, conversationId, actionId);
  if (!action) {
    throw new GatewayError(
        "not-found", "That suggestion is no longer available.");
  }
  if (action.status !== "pending") {
    return {status: "noop", assistantText: null, actionId};
  }

  await store.markPendingAction(uid, conversationId, actionId, "cancelled");
  await store.markProposalMessage(uid, conversationId, actionId, "cancelled");
  const text = "Okay — I won't add that.";
  await store.appendMessage(uid, conversationId, {
    role: "assistant",
    content: text,
    createdAt: clock(),
  });
  return {status: "cancelled", assistantText: text, actionId};
}

module.exports = {
  persistProposal,
  requireMealInPlan,
  applyProposedAction,
  resultLineFor,
  confirmAction,
  cancelAction,
};
