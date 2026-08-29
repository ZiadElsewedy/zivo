/**
 * The server-side MUTATING tool registry for the `aiChat` gateway (ADR-003).
 *
 * These tools are declared to the model but are **non-executing**: when the
 * model calls one, the gateway does NOT write. It calls `validate(input)` here
 * to produce a normalized, fully-validated payload (or throw), persists a
 * pending action, and asks the user to confirm. Only an explicit user confirm
 * (`aiConfirmAction`) performs the actual Firestore write, server-side.
 *
 * `validate` returns JSON-safe normalized data (dates as ISO strings) so it is
 * pure and runs offline under `node --test`; the `store` layer converts to
 * Firestore `Timestamp`s at write time. Field constraints mirror the Firestore
 * rules and the manual capture forms exactly (see `firestore.rules` and the
 * Firestore repository write shapes under lib/features).
 *
 * Expenses (create/edit/delete) + diet meal toggling (2026: create_task/
 * create_event were removed along with the Schedule/Tasks features they
 * backed — see the Gym+Diet specialization). Editing and deleting are
 * confirm-gated exactly like creating: the model must first identify the
 * exact record (its `id`, from get_expenses) and every change still waits on
 * the user's Confirm before any write happens.
 */

const {dayKeyFor, resolveDietDay} = require("./dates");

const EXPENSE_CATEGORIES = ["food", "coffee", "transport", "groceries", "other"];
const DEFAULT_CURRENCY = "EGP";
const MAX_NOTE_CHARS = 500;

/** Thrown by `validate` when a proposed input can't be turned into a write. */
class ValidationError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "ValidationError";
  }
}

/**
 * A trimmed non-empty string of at most `max` chars, or throws.
 * @param {*} value
 * @param {string} label
 * @param {number} max
 * @return {string}
 */
function requireText(value, label, max) {
  const text = (value == null ? "" : String(value)).trim();
  if (!text) throw new ValidationError(`A ${label} is required.`);
  if (text.length > max) throw new ValidationError(`That ${label} is too long.`);
  return text;
}

/**
 * A trimmed string of at most `max` chars, or null when absent/blank.
 * @param {*} value
 * @param {string} label
 * @param {number} max
 * @return {?string}
 */
function optionalText(value, label, max) {
  if (value == null || String(value).trim() === "") return null;
  return requireText(value, label, max);
}

/**
 * A positive integer amount in minor units, or throws.
 * @param {*} value
 * @return {number}
 */
function requireAmountMinor(value) {
  if (!Number.isInteger(value) || value < 0) {
    throw new ValidationError("The amount must be a whole number of minor units (e.g. 1200 for 12.00).");
  }
  if (value === 0) throw new ValidationError("The amount can't be zero.");
  return value;
}

/**
 * `value` validated against the expense category enum, or throws.
 * @param {*} value
 * @return {string}
 */
function requireCategory(value) {
  const category = String(value || "").trim();
  if (!EXPENSE_CATEGORIES.includes(category)) {
    throw new ValidationError(`Category must be one of: ${EXPENSE_CATEGORIES.join(", ")}.`);
  }
  return category;
}

/**
 * A minor-units integer rendered as a fixed-2 major-unit string, or null.
 * @param {?number} amountMinor
 * @return {?string}
 */
function majorAmount(amountMinor) {
  return typeof amountMinor === "number" ?
    (amountMinor / 100).toFixed(2) : null;
}

/**
 * `value` parsed as an ISO 8601 instant, returned as an ISO string, or throws.
 * @param {*} value
 * @param {string} label
 * @return {string}
 */
function requireIso(value, label) {
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) {
    throw new ValidationError(`The ${label} isn't a valid date/time.`);
  }
  return date.toISOString();
}

/**
 * Optional ISO instant → ISO string or null.
 * @param {*} value
 * @param {string} label
 * @return {?string}
 */
function optionalIso(value, label) {
  if (value == null || value === "") return null;
  return requireIso(value, label);
}

const CREATE_EXPENSE = {
  name: "create_expense",
  mutating: true,
  kind: "create_expense",
  description:
    "Propose logging an expense (does not save until the user confirms). " +
    "Requires amountMinor (integer, minor units — e.g. 1200 = 12.00) and " +
    "category (one of: food, coffee, transport, groceries, other). Optional: " +
    "currency (default EGP), note, spentAt (ISO 8601, default now).",
  inputSchema: {
    type: "object",
    properties: {
      amountMinor: {type: "integer", description: "minor units, e.g. 1200 = 12.00"},
      category: {type: "string", enum: EXPENSE_CATEGORIES},
      currency: {type: "string"},
      note: {type: "string"},
      spentAt: {type: "string", description: "ISO 8601, optional"},
    },
    required: ["amountMinor", "category"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload.
   */
  validate(input) {
    const amountMinor = requireAmountMinor(input.amountMinor);
    const category = requireCategory(input.category);
    const currency = (input.currency ?
      String(input.currency).trim() : DEFAULT_CURRENCY).toUpperCase();
    const note = optionalText(input.note, "note", MAX_NOTE_CHARS);
    return {
      amountMinor,
      currency,
      category,
      note,
      spentAtIso: optionalIso(input.spentAt, "spent-at time"),
    };
  },
  fields(v) {
    return {
      amount: (v.amountMinor / 100).toFixed(2),
      currency: v.currency,
      category: v.category,
      note: v.note,
    };
  },
  summarize(v) {
    return `Log ${(v.amountMinor / 100).toFixed(2)} ${v.currency} on ${v.category}` +
      (v.note ? ` (${v.note})` : "");
  },
  result(v) {
    return `Logged expense · ${(v.amountMinor / 100).toFixed(2)} ${v.currency} · ${v.category}`;
  },
};

const MARK_MEAL_EATEN = {
  name: "mark_meal_eaten",
  mutating: true,
  kind: "mark_meal_eaten",
  description:
    "Propose marking a meal from the user's active diet plan as eaten (or " +
    "not eaten) for a day — does not save until the user confirms. Requires " +
    "mealId: use an id EXACTLY as it appeared in get_today/get_diet output. " +
    "Optional: eaten (default true; false to undo), date (ISO 8601, default " +
    "today), label (the meal's name, shown on the confirmation card).",
  inputSchema: {
    type: "object",
    properties: {
      mealId: {type: "string", description: "exact id from get_today/get_diet"},
      label: {type: "string", description: "meal name for the confirmation card"},
      eaten: {type: "boolean", description: "true (default) to mark eaten; false to undo"},
      date: {type: "string", description: "ISO 8601 day, optional, default today"},
    },
    required: ["mealId"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload.
   */
  validate(input) {
    const mealId = requireText(input.mealId, "meal id", 200);
    const label = input.label == null || String(input.label).trim() === "" ?
      null : requireText(input.label, "label", 200);
    return {
      mealId,
      label,
      eaten: input.eaten === undefined ? true : input.eaten === true,
      dateIso: optionalIso(input.date, "date"),
    };
  },
  /**
   * Checks the proposed `mealId` against the user's ACTUAL active plan before
   * the proposal is ever shown, and returns the facts the write should use
   * rather than the ones the model claimed.
   *
   * `validate` can only prove the id is a non-empty string — and a string is
   * exactly what a model can invent. Without this, a hallucinated or stale id
   * survived Confirm and wrote a `dietEntries` doc referencing a meal that
   * doesn't exist: an orphan that counts toward nothing, shows up nowhere in
   * the app, and silently makes "2 of 4 meals eaten" wrong. The Firestore
   * rules can't catch it either (they type-check fields, they can't join
   * against the plan), so this is the only place the check can live.
   *
   * Two things are taken from the plan rather than the model: the resolved
   * `dayKey` (so the write can't drift to another day between propose and
   * confirm) and the meal's real `label` (so the confirmation card names the
   * meal the plan names, not the one the model remembered).
   *
   * @param {!Object} args
   * @param {!Object} args.store
   * @param {string} args.uid
   * @param {!Object} args.validated
   * @param {!Date} args.now
   * @param {number=} args.offsetMinutes
   * @return {!Promise<!Object>} A patch merged into the validated payload.
   */
  async verify({store, uid, validated, now, offsetMinutes}) {
    const date = validated.dateIso ? new Date(validated.dateIso) : now;
    const dayKey = dayKeyFor(date, offsetMinutes);

    const plan = await store.getActiveDietPlan(uid);
    if (!plan) {
      throw new ValidationError(
          "There's no active diet plan, so there's no meal to mark. Tell " +
          "the user that instead of guessing a meal.");
    }
    const day = resolveDietDay(plan.days || [], date, offsetMinutes);
    if (!day) {
      throw new ValidationError(
          `The plan "${plan.name}" has no meals for ${dayKey}. Say so ` +
          "instead of picking a meal from another day.");
    }
    const meals = Array.isArray(day.meals) ? day.meals : [];
    const meal = meals.find((m) => m && m.id === validated.mealId);
    if (!meal) {
      const available = meals
          .map((m) => `${m.label} (id ${m.id})`)
          .join("; ") || "none";
      throw new ValidationError(
          `No meal with id "${validated.mealId}" exists in the plan for ` +
          `${dayKey}. Call get_diet and use an exact id from it. Meals ` +
          `that day: ${available}.`);
    }
    return {dayKey, label: meal.label};
  },
  fields(v) {
    return {
      meal: v.label || v.mealId,
      state: v.eaten ? "eaten" : "not eaten",
    };
  },
  summarize(v) {
    return `Mark ${v.label || v.mealId} ${v.eaten ? "eaten" : "not eaten"}`;
  },
  result(v) {
    return `Marked ${v.label || v.mealId} ${v.eaten ? "eaten" : "not eaten"}.`;
  },
};

/**
 * Builds the human "what's changing" clause shared by edit_expense's summary
 * and result line from a validated patch — "40.00 EGP, food" etc.
 * @param {!Object} v A validated edit_expense payload.
 * @return {string}
 */
function editChangeClause(v) {
  const parts = [];
  if (v.amountMinor !== undefined) {
    parts.push(`${majorAmount(v.amountMinor)} ${v.currency || ""}`.trim());
  } else if (v.currency !== undefined) {
    parts.push(v.currency);
  }
  if (v.category !== undefined) parts.push(v.category);
  if (v.note !== undefined) parts.push(`note "${v.note}"`);
  if (v.spentAtIso !== undefined) parts.push("a new date");
  return parts.join(", ");
}

const EDIT_EXPENSE = {
  name: "edit_expense",
  mutating: true,
  kind: "edit_expense",
  description:
    "Propose editing an existing expense (does not save until the user " +
    "confirms). Requires expenseId — use an id EXACTLY as it appeared in " +
    "get_expenses output; never invent one. Provide a short human `label` " +
    "naming the expense as it is NOW (e.g. 'coffee 40.00 EGP') for the " +
    "confirmation card, plus at least one field to change: amountMinor " +
    "(integer minor units, e.g. 6000 = 60.00), category (one of: food, " +
    "coffee, transport, groceries, other), currency, note, spentAt (ISO " +
    "8601). Only pass the fields you want changed.",
  inputSchema: {
    type: "object",
    properties: {
      expenseId: {type: "string", description: "exact id from get_expenses"},
      label: {type: "string", description: "the expense as it is now, for the card"},
      amountMinor: {type: "integer", description: "new amount in minor units"},
      category: {type: "string", enum: EXPENSE_CATEGORIES},
      currency: {type: "string"},
      note: {type: "string"},
      spentAt: {type: "string", description: "ISO 8601, optional"},
    },
    required: ["expenseId"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload — expenseId/label plus only the
   *   fields being changed (absent keys mean "leave as-is").
   */
  validate(input) {
    const expenseId = requireText(input.expenseId, "expense id", 200);
    const label = optionalText(input.label, "label", 200);
    const patch = {expenseId, label};
    if (input.amountMinor !== undefined && input.amountMinor !== null) {
      patch.amountMinor = requireAmountMinor(input.amountMinor);
    }
    if (input.category !== undefined && input.category !== null &&
        String(input.category).trim() !== "") {
      patch.category = requireCategory(input.category);
    }
    if (input.currency !== undefined && input.currency !== null &&
        String(input.currency).trim() !== "") {
      patch.currency = String(input.currency).trim().toUpperCase();
    }
    if (input.note !== undefined && input.note !== null &&
        String(input.note).trim() !== "") {
      patch.note = requireText(input.note, "note", MAX_NOTE_CHARS);
    }
    if (input.spentAt !== undefined && input.spentAt !== null &&
        String(input.spentAt).trim() !== "") {
      patch.spentAtIso = requireIso(input.spentAt, "spent-at time");
    }
    const changed = ["amountMinor", "category", "currency", "note", "spentAtIso"]
        .some((k) => patch[k] !== undefined);
    if (!changed) {
      throw new ValidationError(
          "Tell me what to change about that expense (amount, category, …).");
    }
    return patch;
  },
  fields(v) {
    return {
      action: "edit",
      target: v.label || null,
      amount: majorAmount(v.amountMinor),
      currency: v.currency || null,
      category: v.category || null,
      note: v.note || null,
    };
  },
  summarize(v) {
    const target = v.label ? ` ${v.label}` : "";
    const clause = editChangeClause(v);
    return `Update${target}${clause ? ` → ${clause}` : ""}`;
  },
  result(v) {
    const target = v.label ? ` · ${v.label}` : "";
    const clause = editChangeClause(v);
    return `Updated expense${target}${clause ? ` → ${clause}` : ""}`;
  },
};

const DELETE_EXPENSE = {
  name: "delete_expense",
  mutating: true,
  kind: "delete_expense",
  description:
    "Propose deleting an existing expense (does not delete until the user " +
    "confirms). Requires expenseId — use an id EXACTLY as it appeared in " +
    "get_expenses output; never invent one. Provide a short human `label` " +
    "naming the expense (e.g. 'coffee 40.00 EGP on Aug 25') and, for a clear " +
    "confirmation card, the expense's current amountMinor, currency, and " +
    "category (display only — nothing is written).",
  inputSchema: {
    type: "object",
    properties: {
      expenseId: {type: "string", description: "exact id from get_expenses"},
      label: {type: "string", description: "the expense being removed, for the card"},
      amountMinor: {type: "integer", description: "current amount, for the card"},
      currency: {type: "string"},
      category: {type: "string"},
    },
    required: ["expenseId"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload — the id to delete plus display-only
   *   context for the confirmation card and history line.
   */
  validate(input) {
    const expenseId = requireText(input.expenseId, "expense id", 200);
    const label = optionalText(input.label, "label", 200);
    const out = {expenseId, label};
    if (input.amountMinor !== undefined && input.amountMinor !== null &&
        Number.isInteger(input.amountMinor) && input.amountMinor >= 0) {
      out.amountMinor = input.amountMinor;
    }
    if (input.currency) {
      out.currency = String(input.currency).trim().toUpperCase();
    }
    if (input.category) out.category = String(input.category).trim();
    return out;
  },
  fields(v) {
    return {
      action: "delete",
      target: v.label || null,
      amount: majorAmount(v.amountMinor),
      currency: v.currency || null,
      category: v.category || null,
    };
  },
  summarize(v) {
    const amount = majorAmount(v.amountMinor);
    const detail = v.label ||
      [amount ? `${amount} ${v.currency || ""}`.trim() : null, v.category]
          .filter(Boolean).join(" · ");
    return `Delete ${detail || "this expense"}`;
  },
  result(v) {
    const amount = majorAmount(v.amountMinor);
    const detail = v.label ||
      [amount ? `${amount} ${v.currency || ""}`.trim() : null, v.category]
          .filter(Boolean).join(" · ");
    return `Deleted expense${detail ? ` · ${detail}` : ""}`;
  },
};

const mutatingTools = [
  CREATE_EXPENSE,
  EDIT_EXPENSE,
  DELETE_EXPENSE,
  MARK_MEAL_EATEN,
];
const mutatingToolsByName = new Map(mutatingTools.map((t) => [t.name, t]));

module.exports = {
  mutatingTools,
  mutatingToolsByName,
  ValidationError,
  EXPENSE_CATEGORIES,
};
