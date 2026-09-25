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

const {dayKeyFor, resolveDietDay} = require("../shared/dates");
const {normalizeItem, resolveAndCompute} = require("../../nutrition/resolve");
const {upNextDay, dayAfter, dayName} = require("./workout_rotation");

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

const MAX_LOG_ITEMS = 20;

/**
 * A short "3 foods · 720 kcal" / "chicken breast (200 g) · 330 kcal" clause for
 * a validated (verified) log_food payload, shared by summary and result.
 * @param {!Object} v
 * @return {string}
 */
function logClause(v) {
  const entries = Array.isArray(v.entries) ? v.entries : [];
  const kcal = v.totals ? v.totals.kcal : null;
  if (entries.length === 1) {
    const e = entries[0];
    const qty = Number.isInteger(e.quantity) ? e.quantity : e.quantity;
    return `${e.foodName} (${qty} ${e.unit})` +
      (kcal != null ? ` · ${kcal} kcal` : "");
  }
  const count = entries.length || (Array.isArray(v.items) ? v.items.length : 0);
  return `${count} food${count === 1 ? "" : "s"}` +
    (kcal != null ? ` · ${kcal} kcal` : "");
}

const LOG_FOOD = {
  name: "log_food",
  mutating: true,
  kind: "log_food",
  description:
    "Propose logging food the user actually ate to their food log — does not " +
    "save until the user confirms. Use this for 'I ate two eggs and 100g of " +
    "rice'. Each item takes a `foodId` (from resolve_food, preferred) OR a " +
    "`query`, plus `quantity` and `unit`. You do NOT provide calories or " +
    "macros — ZIVO computes them from the catalog; a food it can't resolve " +
    "(ambiguous, not found, or an unconvertible unit) comes back as an error " +
    "for you to fix (resolve_food and pass a foodId), never a guess. Optional: " +
    "date (ISO 8601, default today). Log only what the user says they ate — " +
    "to tick a meal off their plan, use mark_meal_eaten instead.",
  inputSchema: {
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            foodId: {type: "string", description: "from resolve_food, preferred"},
            query: {type: "string", description: "the food, if no foodId"},
            preparation: {type: "string", enum: ["raw", "cooked", "dry"]},
            quantity: {type: "number"},
            unit: {type: "string", description: "g, oz, piece, …"},
          },
        },
      },
      date: {type: "string", description: "ISO 8601 day, optional, default today"},
    },
    required: ["items"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload — the normalized items plus the day.
   */
  validate(input) {
    const raw = Array.isArray(input.items) ? input.items : [];
    if (raw.length === 0) {
      throw new ValidationError("Tell me what food to log.");
    }
    if (raw.length > MAX_LOG_ITEMS) {
      throw new ValidationError(
          `That's a lot at once — log at most ${MAX_LOG_ITEMS} items.`);
    }
    let items;
    try {
      items = raw.map(normalizeItem);
    } catch (err) {
      // normalizeItem throws a plain Error; surface it as a validation error so
      // the gateway feeds it back to the model to correct.
      throw new ValidationError(err.message);
    }
    return {items, dateIso: optionalIso(input.date, "date")};
  },
  /**
   * Resolves and prices every item against the REAL catalog (plus the user's
   * custom foods) before the proposal is ever shown, and returns the fully
   * computed entries the write will use.
   *
   * This is where the trust boundary is enforced: the model names foods and
   * amounts, and the server — never the model — turns them into calories, the
   * same way the app's log sheet does. An item that is ambiguous, absent, or
   * whose unit can't be converted is refused with a message the model can act
   * on, so a guessed number can never reach the confirm button. The nutrition
   * is snapshotted into the entries here, so it's frozen at log time and can't
   * drift if the catalog is rebuilt later.
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
    const customFoods = await store.listCustomFoods(uid);

    const entries = [];
    let kcal = 0;
    let proteinG = 0;
    let carbsG = 0;
    let fatG = 0;
    for (const item of validated.items) {
      const result = resolveAndCompute(item, customFoods);
      const named = item.query || item.foodId;
      if (result.outcome === "notFound") {
        throw new ValidationError(
            `"${named}" isn't in the nutrition catalog. Tell the user and ` +
            "offer to log it as a custom food — don't guess its calories.");
      }
      if (result.outcome === "ambiguous") {
        const options = result.candidates
            .map((c) => `${c.name} (${c.per100gKcal} kcal/100g, id ${c.foodId})`)
            .join("; ");
        throw new ValidationError(
            `"${named}" matches several foods that differ in calories: ` +
            `${options}. Ask the user which they mean, then pass that foodId.`);
      }
      if (result.outcome === "unresolvedMeasure") {
        const measures = result.availableMeasures.length ?
          result.availableMeasures.join(", ") : "grams (g) or ounces (oz)";
        throw new ValidationError(
            `Can't measure "${named}" in ${result.unit}. Measures that work: ` +
            `${measures}. Ask the user to give the amount in one of those.`);
      }
      entries.push({
        dayKey,
        foodId: result.foodId,
        foodName: result.name,
        quantity: result.quantity,
        unit: result.unit,
        grams: result.grams,
        kcal: result.kcal,
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        source: result.source,
        sourceRef: result.sourceRef,
        // The user told us they ate this — the most trustworthy kind of entry,
        // and not an AI estimate: the figures are the catalog's, not a guess.
        origin: "logged",
        estimated: false,
        mealId: null,
      });
      kcal += result.kcal;
      proteinG += result.proteinG;
      carbsG += result.carbsG;
      fatG += result.fatG;
    }

    return {
      dayKey,
      entries,
      totals: {
        kcal: Math.round(kcal),
        proteinG: Math.round(proteinG * 10) / 10,
        carbsG: Math.round(carbsG * 10) / 10,
        fatG: Math.round(fatG * 10) / 10,
      },
    };
  },
  fields(v) {
    const entries = Array.isArray(v.entries) ? v.entries : [];
    return {
      items: entries.map((e) => ({
        name: e.foodName,
        quantity: e.quantity,
        unit: e.unit,
        kcal: e.kcal,
      })),
      totalKcal: v.totals ? v.totals.kcal : null,
      count: entries.length,
    };
  },
  summarize(v) {
    return `Log ${logClause(v)}`;
  },
  result(v) {
    return `Logged ${logClause(v)}`;
  },
};

const REPLACE_MEAL_ITEM = {
  name: "replace_meal_item",
  mutating: true,
  // DISCOVER → CHOOSE → MUTATE: a proposal in the same turn as a search that
  // OFFERED options (more than one candidate) is refused by the turn loop —
  // the user hasn't chosen yet. A one-candidate search (pricing the food the
  // user named themselves) doesn't count as offering.
  refusedAfterOffer: "search_food_alternatives",
  kind: "replace_meal_item",
  description:
    "Propose swapping one item in the active plan for an alternative — " +
    "does not save until confirmed. ONLY after the user explicitly chose " +
    "the replacement (picked an option you showed, or named it " +
    "themselves) — never in the turn you searched for options. Identify " +
    "the item with mealId, itemIndex and itemName exactly as they " +
    "appeared in get_today/get_diet or search_food_alternatives' " +
    "`original`. You do NOT provide calories or macros — ZIVO computes " +
    "them from the catalog.",
  inputSchema: {
    type: "object",
    properties: {
      mealId: {type: "string", description: "exact id from get_today/get_diet"},
      itemIndex: {
        type: "integer",
        description: "the item's `index` from get_today/get_diet, within that meal",
      },
      itemName: {
        type: "string",
        description: "the item's current exact name, to catch a stale reference",
      },
      foodId: {
        type: "string",
        description: "from search_food_alternatives' alternatives, or resolve_food",
      },
      quantity: {type: "number"},
      unit: {type: "string", description: "g, oz, piece, …"},
      date: {type: "string", description: "ISO 8601 day, optional, default today"},
    },
    required: ["mealId", "itemIndex", "itemName", "foodId", "quantity", "unit"],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload — the item reference plus the
   *   normalized replacement reference.
   */
  validate(input) {
    const mealId = requireText(input.mealId, "meal id", 200);
    const itemName = requireText(input.itemName, "item name", 200);
    if (!Number.isInteger(input.itemIndex) || input.itemIndex < 0) {
      throw new ValidationError(
          "A valid item index (the `index` from get_diet) is required.");
    }
    let item;
    try {
      item = normalizeItem({
        foodId: input.foodId, quantity: input.quantity, unit: input.unit,
      });
    } catch (err) {
      throw new ValidationError(err.message);
    }
    return {
      mealId,
      itemIndex: input.itemIndex,
      itemName,
      item,
      dateIso: optionalIso(input.date, "date"),
    };
  },
  /**
   * Re-locates the exact item against the user's REAL active plan (the same
   * "the model can only prove a string, not a fact" discipline as
   * `mark_meal_eaten.verify`) and resolves+prices the replacement through the
   * real catalog (the same discipline as `log_food.verify`) — so neither half
   * of this proposal can be a guess.
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
          "There's no active diet plan, so there's nothing to replace. Tell " +
          "the user that instead of guessing an item.");
    }
    const day = resolveDietDay(plan.days || [], date, offsetMinutes);
    if (!day) {
      throw new ValidationError(
          `The plan "${plan.name}" has no meals for ${dayKey}. Say so ` +
          "instead of picking an item from another day.");
    }
    const meals = Array.isArray(day.meals) ? day.meals : [];
    const meal = meals.find((m) => m && m.id === validated.mealId);
    if (!meal) {
      const available = meals
          .map((m) => `${m.label} (id ${m.id})`)
          .join("; ") || "none";
      throw new ValidationError(
          `No meal with id "${validated.mealId}" exists in the plan for ` +
          `${dayKey}. Call get_diet and use an exact id. Meals that day: ` +
          `${available}.`);
    }
    const items = Array.isArray(meal.items) ? meal.items : [];
    const current = items[validated.itemIndex];
    if (!current || String(current.name || "").trim().toLowerCase() !==
        validated.itemName.trim().toLowerCase()) {
      throw new ValidationError(
          `Item ${validated.itemIndex} in "${meal.label}" isn't ` +
          `"${validated.itemName}" any more — the plan changed. Call ` +
          "get_diet again and use its current index/name.");
    }

    const customFoods = await store.listCustomFoods(uid);
    const result = resolveAndCompute(validated.item, customFoods);
    const named = validated.item.query || validated.item.foodId;
    if (result.outcome === "notFound") {
      throw new ValidationError(
          `"${named}" isn't in the nutrition catalog. Use resolve_food or ` +
          "search_food_alternatives to find a real foodId — don't guess.");
    }
    if (result.outcome === "ambiguous") {
      const options = result.candidates
          .map((c) => `${c.name} (${c.per100gKcal} kcal/100g, id ${c.foodId})`)
          .join("; ");
      throw new ValidationError(
          `"${named}" matches several foods that differ in calories: ` +
          `${options}. Pass the exact foodId.`);
    }
    if (result.outcome === "unresolvedMeasure") {
      const measures = result.availableMeasures.length ?
        result.availableMeasures.join(", ") : "grams (g) or ounces (oz)";
      throw new ValidationError(
          `Can't measure "${named}" in ${result.unit}. Measures that work: ` +
          `${measures}. Ask the user to give the amount in one of those.`);
    }

    return {
      dayKey,
      mealLabel: meal.label,
      originalItemName: current.name,
      originalCalories: current.calories,
      newItem: {
        name: result.name,
        quantity: result.quantity,
        unit: result.unit,
        calories: Math.round(result.kcal),
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        // Priced through the catalog, never a guess — same standing as any
        // other item a person adds to their plan.
        estimated: false,
      },
    };
  },
  fields(v) {
    return {
      meal: v.mealLabel,
      from: v.originalItemName,
      fromCalories: v.originalCalories,
      to: v.newItem ? v.newItem.name : null,
      toCalories: v.newItem ? v.newItem.calories : null,
    };
  },
  summarize(v) {
    return `Replace ${v.originalItemName} with ${v.newItem.name} in ${v.mealLabel}`;
  },
  result(v) {
    return `Replaced ${v.originalItemName} with ${v.newItem.name} in ${v.mealLabel}`;
  },
};

const CUSTOM_FOOD_PREPARATIONS = ["raw", "cooked", "dry"];

/**
 * A finite number in `[0, max]`, or throws — the same "don't trust the
 * model's arithmetic" discipline as every other bounds check here.
 * @param {*} value
 * @param {string} label
 * @param {number} max
 * @return {number}
 */
function requireNonNegativeNumber(value, label, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > max) {
    throw new ValidationError(`${label} must be a number between 0 and ${max}.`);
  }
  return n;
}

const CREATE_CUSTOM_FOOD = {
  name: "create_custom_food",
  mutating: true,
  kind: "create_custom_food",
  description:
    "Save a food ZIVO's catalog doesn't have as the user's own custom food — " +
    "from a search_food_product candidate the user picked, or from figures " +
    "the user stated themselves. Does not save until confirmed. Pass the " +
    "figures EXACTLY as they came from search_food_product or from the user " +
    "— never adjust, round, or estimate them yourself. Once saved, resolve_food " +
    "and log_food will find it like any other food.",
  inputSchema: {
    type: "object",
    properties: {
      name: {type: "string"},
      kcalPer100g: {type: "number"},
      proteinPer100g: {type: "number"},
      carbsPer100g: {type: "number"},
      fatPer100g: {type: "number"},
      preparation: {type: "string", enum: CUSTOM_FOOD_PREPARATIONS},
    },
    required: [
      "name", "kcalPer100g", "proteinPer100g", "carbsPer100g", "fatPer100g",
    ],
  },
  /**
   * @param {!Object} input
   * @return {!Object} Validated payload — the normalized custom-food fields.
   */
  validate(input) {
    const name = requireText(input.name, "food name", 200);
    const kcalPer100g = requireNonNegativeNumber(
        input.kcalPer100g, "Calories per 100g", 9000);
    const proteinPer100g = requireNonNegativeNumber(
        input.proteinPer100g, "Protein per 100g", 100);
    const carbsPer100g = requireNonNegativeNumber(
        input.carbsPer100g, "Carbs per 100g", 100);
    const fatPer100g = requireNonNegativeNumber(
        input.fatPer100g, "Fat per 100g", 100);
    const prep = typeof input.preparation === "string" ?
      input.preparation.trim().toLowerCase() : null;
    return {
      name,
      kcalPer100g,
      proteinPer100g,
      carbsPer100g,
      fatPer100g,
      preparation:
        prep && CUSTOM_FOOD_PREPARATIONS.includes(prep) ? prep : null,
    };
  },
  fields(v) {
    return {
      name: v.name,
      kcalPer100g: v.kcalPer100g,
      proteinPer100g: v.proteinPer100g,
      carbsPer100g: v.carbsPer100g,
      fatPer100g: v.fatPer100g,
    };
  },
  summarize(v) {
    return `Save "${v.name}" as a custom food · ${Math.round(v.kcalPer100g)} kcal/100g`;
  },
  result(v) {
    return `Saved "${v.name}" as a custom food`;
  },
};

const CHANGE_WORKOUT_DAY = {
  name: "change_workout_day",
  mutating: true,
  // Laid out both ways this turn → the user hasn't picked skip or swap yet.
  refusedAfterOffer: "preview_workout_change",
  kind: "change_workout_day",
  description:
    "Propose changing which workout the user does today, in their " +
    "rotation — does not save until confirmed. 'swap' trades today's " +
    "scheduled day with `dayId` (that one today, the scheduled one " +
    "straight after); 'skip' drops today's scheduled day from this round " +
    "and makes `dayId` today's workout; 'skip' without `dayId` just moves " +
    "on to the next day. ONLY when the user made clear which they want — " +
    "otherwise preview_workout_change + ask_choice first. `dayId` must " +
    "come from get_workout_schedule.",
  inputSchema: {
    type: "object",
    properties: {
      mode: {type: "string", enum: ["swap", "skip"]},
      dayId: {
        type: "string",
        description: "the day to train today, from get_workout_schedule",
      },
    },
    required: ["mode"],
  },
  /**
   * @param {!Object} input
   * @return {{mode: string, dayId: ?string}}
   */
  validate(input) {
    const mode = input.mode === "swap" || input.mode === "skip" ?
      input.mode : null;
    if (!mode) {
      throw new ValidationError("mode must be 'swap' or 'skip'.");
    }
    const dayId = input.dayId == null || input.dayId === "" ?
      null : requireText(input.dayId, "day id", 200);
    if (mode === "swap" && !dayId) {
      throw new ValidationError(
          "A swap needs the dayId of the workout to do today instead.");
    }
    return {mode, dayId};
  },
  /**
   * Proves the change against the user's REAL rotation: what's due now, and
   * that the day they want exists and isn't already today's.
   * @param {!Object} args
   * @return {!Promise<!Object>}
   */
  async verify({store, uid, validated}) {
    const plan = await store.getActiveWorkoutPlan(uid);
    if (!plan || !Array.isArray(plan.days) || plan.days.length < 2) {
      throw new ValidationError(
          "The user has no split with more than one day, so there's no " +
          "rotation to change. Say so.");
    }
    const due = upNextDay(plan.days, plan.cycleCursor);
    const target = validated.dayId ?
      plan.days.find((d) => d.id === validated.dayId) :
      dayAfter(plan.days, due.id);
    if (!target) {
      const ids = plan.days.map((d) => `${dayName(d)} (id ${d.id})`)
          .join("; ");
      throw new ValidationError(
          `No day with id "${validated.dayId}" in the split. Call ` +
          `get_workout_schedule and use an exact dayId. Days: ${ids}.`);
    }
    if (target.id === due.id) {
      throw new ValidationError(
          `${dayName(due)} is already today's workout — nothing to change. ` +
          "Tell the user.");
    }
    const upAfter = validated.mode === "swap" ? due : dayAfter(plan.days,
        target.id);
    return {
      planId: plan.id,
      dueDayId: due.id,
      dueName: dayName(due),
      targetDayId: target.id,
      targetName: dayName(target),
      thenName: upAfter ? dayName(upAfter) : null,
    };
  },
  fields(v) {
    return {
      mode: v.mode,
      from: v.dueName,
      to: v.targetName,
      then: v.thenName,
    };
  },
  summarize(v) {
    return v.mode === "swap" ?
      `Swap ${v.dueName} with ${v.targetName} — ${v.targetName} today, ` +
        `${v.dueName} next` :
      `Skip ${v.dueName} — ${v.targetName} today`;
  },
  result(v) {
    return v.mode === "swap" ?
      `Swapped — ${v.targetName} is today's workout, ${v.dueName} is next` :
      `Skipped ${v.dueName} — ${v.targetName} is today's workout`;
  },
};

const mutatingTools = [
  CREATE_EXPENSE,
  EDIT_EXPENSE,
  DELETE_EXPENSE,
  MARK_MEAL_EATEN,
  LOG_FOOD,
  CREATE_CUSTOM_FOOD,
  REPLACE_MEAL_ITEM,
  CHANGE_WORKOUT_DAY,
];
const mutatingToolsByName = new Map(mutatingTools.map((t) => [t.name, t]));

module.exports = {
  mutatingTools,
  mutatingToolsByName,
  ValidationError,
  EXPENSE_CATEGORIES,
};
