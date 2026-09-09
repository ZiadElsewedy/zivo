/**
 * The server-side ELICITATION tool registry for the `aiChat` gateway — the
 * coach's way to PAUSE a turn and ask the user something, rather than guess.
 *
 * Like the mutating tools (`mutations.js`), these are declared to the model but
 * are **non-executing**: when the model calls one, the gateway does NOT answer
 * for the user. It `validate`s the input into a normalized card spec, appends
 * that card as an assistant message, and ends the turn. The user's answer comes
 * back as a normal next turn (a plain `aiChat` send), so — unlike a write
 * proposal — there is no confirm/execute half here and no pending-action doc:
 * a question resolves by being answered, not confirmed.
 *
 * Phase 1 ships ONE tool, `ask_choice` (option chips), the lowest-risk slice:
 * pure clarification, no persistence. `request_input` (a data-collection form
 * that can write back to the profile) is a later phase and will live here too.
 *
 * `validate` is pure and JSON-safe so it runs offline under `node --test`.
 */

/** Thrown by `validate` when a question can't be turned into a card. */
class ElicitationError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "ElicitationError";
  }
}

const MAX_PROMPT_CHARS = 300;
const MAX_LABEL_CHARS = 80;
const MAX_VALUE_CHARS = 80;
const MIN_OPTIONS = 2;
const MAX_OPTIONS = 5;

// request_input (the form): a small, bounded set of fields — asking for more
// than a handful at once is a screen, not a chat question.
const MAX_KEY_CHARS = 40;
const MAX_UNIT_CHARS = 16;
const MAX_FIELDS = 4;
const FIELD_TYPES = ["number", "text", "choice"];

/**
 * A trimmed, non-empty string of at most `max` chars, or throws.
 * @param {*} value
 * @param {string} label
 * @param {number} max
 * @return {string}
 */
function requireText(value, label, max) {
  const text = (value == null ? "" : String(value)).trim();
  if (!text) throw new ElicitationError(`A ${label} is required.`);
  if (text.length > max) {
    throw new ElicitationError(`That ${label} is too long.`);
  }
  return text;
}

/**
 * Normalizes one raw option into `{value, label}`. Accepts a bare string
 * (used as both value and label) or an object with `value`/`label` — the model
 * is not always precise about which it sends.
 * @param {*} raw
 * @return {{value: string, label: string}}
 */
function normalizeOption(raw) {
  if (typeof raw === "string") {
    const label = requireText(raw, "option", MAX_LABEL_CHARS);
    return {value: label, label};
  }
  if (raw && typeof raw === "object") {
    const label = requireText(raw.label != null ? raw.label : raw.value,
        "option label", MAX_LABEL_CHARS);
    const value = requireText(raw.value != null ? raw.value : label,
        "option value", MAX_VALUE_CHARS);
    return {value, label};
  }
  throw new ElicitationError("Each option must be text or {value, label}.");
}

/**
 * Normalizes a raw options array into 2–5 distinct `{value, label}` choices,
 * or throws. Shared by `ask_choice` and a `request_input` field of type
 * `choice`, so a picker built either way behaves identically.
 * @param {*} rawOptions
 * @return {!Array<{value: string, label: string}>}
 */
function normalizeOptions(rawOptions) {
  const list = Array.isArray(rawOptions) ? rawOptions : [];
  if (list.length < MIN_OPTIONS) {
    throw new ElicitationError(
        `Give at least ${MIN_OPTIONS} options to choose from.`);
  }
  const options = [];
  const seen = new Set();
  for (const raw of list) {
    if (options.length >= MAX_OPTIONS) break;
    const opt = normalizeOption(raw);
    // Collapse duplicate values so a pick is unambiguous.
    if (seen.has(opt.value)) continue;
    seen.add(opt.value);
    options.push(opt);
  }
  if (options.length < MIN_OPTIONS) {
    throw new ElicitationError(
        `Give at least ${MIN_OPTIONS} distinct options.`);
  }
  return options;
}

/**
 * Normalizes one raw `request_input` field spec into
 * `{key, label, type, required, unit?, options?}`, or throws. An unknown type
 * falls back to free text; a `choice` field must carry valid options.
 * @param {*} raw
 * @return {!Object}
 */
function normalizeField(raw) {
  if (!raw || typeof raw !== "object") {
    throw new ElicitationError("Each field must be an object.");
  }
  const key = requireText(raw.key, "field key", MAX_KEY_CHARS);
  const label = requireText(raw.label, "field label", MAX_LABEL_CHARS);
  const rawType = String(raw.type || "text").trim();
  const type = FIELD_TYPES.includes(rawType) ? rawType : "text";
  const field = {key, label, type, required: raw.required !== false};
  if (raw.unit != null && String(raw.unit).trim() !== "") {
    field.unit = requireText(raw.unit, "unit", MAX_UNIT_CHARS);
  }
  if (type === "choice") field.options = normalizeOptions(raw.options);
  return field;
}

const ASK_CHOICE = {
  name: "ask_choice",
  elicits: true,
  // The assistant-message `kind` the client switches on to render chips.
  messageKind: "choice_request",
  description:
    "Ask the user a multiple-choice question when a good answer depends on a " +
    "choice only they can make — pick this over guessing, or over writing the " +
    "options out as plain text. The turn PAUSES: the user taps one option (or " +
    "more, if allowMultiple) and their pick returns as the next message for " +
    "you to continue from. Do NOT use it to ask for a fact a tool can supply " +
    "(get_today already carries the user's profile, latest weight and age). " +
    "Provide prompt (the question) and 2–5 options as {value, label}; value " +
    "is a stable key, label is what the user sees. Write both in the user's " +
    "language. At most one question per turn.",
  inputSchema: {
    type: "object",
    properties: {
      prompt: {type: "string", description: "the question to ask"},
      options: {
        type: "array",
        description: "2–5 choices",
        items: {
          type: "object",
          properties: {
            value: {type: "string", description: "stable key for the choice"},
            label: {type: "string", description: "what the user sees"},
          },
          required: ["label"],
        },
      },
      allowMultiple: {
        type: "boolean",
        description: "true to let the user pick more than one (default false)",
      },
    },
    required: ["prompt", "options"],
  },
  /**
   * @param {!Object} input
   * @return {{prompt: string, options: !Array<{value: string, label: string}>,
   *   allowMultiple: boolean}}
   */
  validate(input) {
    const prompt = requireText(input.prompt, "question", MAX_PROMPT_CHARS);
    const options = normalizeOptions(input.options);
    return {prompt, options, allowMultiple: input.allowMultiple === true};
  },
  /**
   * The fallback text for a client that doesn't render the card — the question
   * itself.
   * @param {!Object} v A validated payload.
   * @return {string}
   */
  summarize(v) {
    return v.prompt;
  },
  /**
   * The structured spec the client renders the chips from.
   * @param {!Object} v A validated payload.
   * @return {!Object}
   */
  fields(v) {
    return {options: v.options, allowMultiple: v.allowMultiple};
  },
};

const REQUEST_INPUT = {
  name: "request_input",
  elicits: true,
  // The assistant-message `kind` the client switches on to render the form.
  messageKind: "input_request",
  description:
    "Ask the user to fill in a small form when you genuinely lack a specific " +
    "piece of data AND no tool can supply it (get_today already carries the " +
    "user's profile, latest weight and age — read it first). The turn PAUSES: " +
    "the user fills the fields and their entries return as the next message " +
    "for you to continue from. Provide prompt (what you need and why, one " +
    "line) and 1–4 fields. Each field: key (a short stable id like " +
    "'heightCm'), label (what the user sees), type ('number', 'text' or " +
    "'choice'), and optionally unit ('cm', 'kg', …), options (for 'choice', " +
    "2–5 {value, label}), and required (default true). Ask only for the fields " +
    "you truly need, in the user's language. To have a value REMEMBERED into " +
    "the user's profile (so you never ask again), use these exact keys and " +
    "units: 'heightCm' (a number in centimetres) and 'weightKg' (their current " +
    "weight in kilograms). Any other key is used only for this reply. At most " +
    "one question per turn.",
  inputSchema: {
    type: "object",
    properties: {
      prompt: {type: "string", description: "what you need, one line"},
      fields: {
        type: "array",
        description: "1–4 fields to collect",
        items: {
          type: "object",
          properties: {
            key: {type: "string", description: "short stable id, e.g. heightCm"},
            label: {type: "string", description: "what the user sees"},
            type: {type: "string", enum: FIELD_TYPES},
            unit: {type: "string", description: "e.g. cm, kg (optional)"},
            options: {
              type: "array",
              description: "for type 'choice': 2–5 {value, label}",
              items: {
                type: "object",
                properties: {
                  value: {type: "string"},
                  label: {type: "string"},
                },
                required: ["label"],
              },
            },
            required: {type: "boolean", description: "default true"},
          },
          required: ["key", "label"],
        },
      },
    },
    required: ["prompt", "fields"],
  },
  /**
   * @param {!Object} input
   * @return {{prompt: string, fields: !Array<!Object>}}
   */
  validate(input) {
    const prompt = requireText(input.prompt, "prompt", MAX_PROMPT_CHARS);
    const rawFields = Array.isArray(input.fields) ? input.fields : [];
    if (rawFields.length < 1) {
      throw new ElicitationError("Give at least one field to fill in.");
    }
    const fields = [];
    const seen = new Set();
    for (const raw of rawFields) {
      if (fields.length >= MAX_FIELDS) break;
      const field = normalizeField(raw);
      // A repeated key would make the submitted answer ambiguous.
      if (seen.has(field.key)) continue;
      seen.add(field.key);
      fields.push(field);
    }
    if (fields.length < 1) {
      throw new ElicitationError("Give at least one distinct field.");
    }
    return {prompt, fields};
  },
  /**
   * The fallback text for a client that doesn't render the form.
   * @param {!Object} v A validated payload.
   * @return {string}
   */
  summarize(v) {
    return v.prompt;
  },
  /**
   * The structured spec the client renders the form from.
   * @param {!Object} v A validated payload.
   * @return {!Object}
   */
  fields(v) {
    return {fields: v.fields};
  },
};

const elicitationTools = [ASK_CHOICE, REQUEST_INPUT];
const elicitationToolsByName = new Map(
    elicitationTools.map((t) => [t.name, t]));

module.exports = {
  ElicitationError,
  ASK_CHOICE,
  REQUEST_INPUT,
  elicitationTools,
  elicitationToolsByName,
};
