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
 * First slice (owner-approved 2026-08-16): create-only for tasks, expenses,
 * and schedule events. No edits or deletes.
 */

const EXPENSE_CATEGORIES = ["food", "coffee", "transport", "groceries", "other"];
const DEFAULT_CURRENCY = "EGP";
const MAX_TITLE_CHARS = 200;
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

const CREATE_TASK = {
  name: "create_task",
  mutating: true,
  kind: "create_task",
  description:
    "Propose creating a new task (does not save until the user confirms). " +
    "Requires a title. Optional: due (ISO 8601 date/time) and priority " +
    "('high' or 'normal', default 'normal').",
  inputSchema: {
    type: "object",
    properties: {
      title: {type: "string"},
      due: {type: "string", description: "ISO 8601 date/time, optional"},
      priority: {type: "string", enum: ["high", "normal"]},
    },
    required: ["title"],
  },
  /**
   * @param {!Object} input
   * @return {{title: string, dueIso: ?string, priority: boolean}}
   */
  validate(input) {
    return {
      title: requireText(input.title, "task title", MAX_TITLE_CHARS),
      dueIso: optionalIso(input.due, "due date"),
      priority: input.priority === "high",
    };
  },
  /**
   * @param {!Object} v A validated payload.
   * @return {!Object} Card fields (JSON-safe).
   */
  fields(v) {
    return {title: v.title, due: v.dueIso, priority: v.priority ? "High" : "Normal"};
  },
  /**
   * @param {!Object} v A validated payload.
   * @return {string} Human proposal line.
   */
  summarize(v) {
    return `Add task "${v.title}"` +
      (v.dueIso ? ` due ${v.dueIso.slice(0, 10)}` : "") +
      (v.priority ? " (high priority)" : "");
  },
  /**
   * @param {!Object} v A validated payload.
   * @return {string} Deterministic confirmed-result line.
   */
  result(v) {
    return `Added to Tasks · ${v.title}`;
  },
};

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
    const amountMinor = input.amountMinor;
    if (!Number.isInteger(amountMinor) || amountMinor < 0) {
      throw new ValidationError("The amount must be a whole number of minor units (e.g. 1200 for 12.00).");
    }
    if (amountMinor === 0) throw new ValidationError("The amount can't be zero.");
    const category = String(input.category || "").trim();
    if (!EXPENSE_CATEGORIES.includes(category)) {
      throw new ValidationError(`Category must be one of: ${EXPENSE_CATEGORIES.join(", ")}.`);
    }
    const currency = (input.currency ?
      String(input.currency).trim() : DEFAULT_CURRENCY).toUpperCase();
    const note = input.note == null || String(input.note).trim() === "" ?
      null : requireText(input.note, "note", MAX_NOTE_CHARS);
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

const CREATE_EVENT = {
  name: "create_event",
  mutating: true,
  kind: "create_event",
  description:
    "Propose adding a schedule event (does not save until the user confirms). " +
    "Requires title and start (ISO 8601 date/time). Optional: end (ISO 8601) " +
    "and location.",
  inputSchema: {
    type: "object",
    properties: {
      title: {type: "string"},
      start: {type: "string", description: "ISO 8601 date/time"},
      end: {type: "string", description: "ISO 8601 date/time, optional"},
      location: {type: "string"},
    },
    required: ["title", "start"],
  },
  validate(input) {
    const title = requireText(input.title, "event title", MAX_TITLE_CHARS);
    const startIso = requireIso(input.start, "start time");
    const endIso = optionalIso(input.end, "end time");
    if (endIso && new Date(endIso).getTime() < new Date(startIso).getTime()) {
      throw new ValidationError("The end time can't be before the start time.");
    }
    const location = input.location == null || String(input.location).trim() === "" ?
      null : requireText(input.location, "location", MAX_TITLE_CHARS);
    return {title, startIso, endIso, location};
  },
  fields(v) {
    return {
      title: v.title, start: v.startIso, end: v.endIso, location: v.location,
    };
  },
  summarize(v) {
    return `Add "${v.title}" to your schedule at ${v.startIso.slice(0, 16).replace("T", " ")}` +
      (v.location ? ` (${v.location})` : "");
  },
  result(v) {
    return `Added to Schedule · ${v.title}`;
  },
};

const mutatingTools = [CREATE_TASK, CREATE_EXPENSE, CREATE_EVENT];
const mutatingToolsByName = new Map(mutatingTools.map((t) => [t.name, t]));

module.exports = {
  mutatingTools,
  mutatingToolsByName,
  ValidationError,
  EXPENSE_CATEGORIES,
};
